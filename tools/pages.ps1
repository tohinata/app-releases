# 다운로드 페이지: README 의 앱 표 + apps\<앱키>.md (앱마다 한 페이지, 받기 링크가 맨 위).
# Publish-Release 가 릴리스할 때마다 부른다. 직접 다시 만들려면 9-2_다운로드페이지갱신.bat.
. (Join-Path $PSScriptRoot 'apps.ps1')

function Get-AllApps {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($a in $AndroidApps) { $list.Add(@{ Key = $a.Key; Name = $a.Name; Kind = '안드로이드' }) }
    foreach ($a in $JavaApps)    { $list.Add(@{ Key = $a.Key; Name = $a.Name; Kind = '안드로이드' }) }
    foreach ($a in $WindowsApps) { $list.Add(@{ Key = $a.Key; Name = $a.Name; Kind = '윈도우' }) }
    foreach ($a in $WebApps)     { $list.Add(@{ Key = $a.Key; Name = $a.Name; Kind = '윈도우 (HTML)' }) }
    foreach ($a in $ChromeApps)  { $list.Add(@{ Key = $a.Key; Name = $a.Name; Kind = '크롬 확장' }) }
    return $list
}

function Format-Day($v) {
    if ($v -is [datetime]) { return $v.ToLocalTime().ToString('yyyy-MM-dd') }
    $s = "$v"
    if ($s.Length -ge 10) { return $s.Substring(0, 10) }
    return $s
}

function Get-InstallGuide([string]$Platform, [string]$Exe) {
    switch ($Platform) {
        'android' {
            return "폰에서 이 페이지를 열고 위 링크를 누르면 APK 를 받습니다. 받은 파일을 열어 설치하세요.`n`n" +
                "- 처음 한 번 「출처를 알 수 없는 앱 설치」 허용이 필요합니다.`n" +
                "- 한 번 설치하면 그다음부터는 앱이 알아서 새 버전을 확인하고 업데이트합니다."
        }
        'windows' {
            $run = if ($Exe) { "``$Exe`` 를" } else { "프로그램을" }
            return "zip 을 받아 원하는 폴더에 풀고 $run 실행하세요.`n`n" +
                "- 「Windows의 PC 보호」 창이 뜨면 [추가 정보] → [실행].`n" +
                "- 한 번 설치하면 그다음부터는 실행할 때 알아서 업데이트합니다."
        }
        'web' {
            return "zip 을 받아 원하는 폴더에 풀고 ``1-1_실행.bat`` 을 실행하세요.`n`n" +
                "- 한 번 설치하면 그다음부터는 실행할 때 알아서 업데이트합니다."
        }
        'chrome' {
            return "zip 을 받아 폴더에 푼 뒤, 크롬 주소창에 ``chrome://extensions`` → 오른쪽 위 [개발자 모드] 켜기 → " +
                "[압축해제된 확장 프로그램을 로드합니다] → 푼 폴더를 고르세요.`n`n" +
                "- 새 버전이 나오면 확장 아이콘에 NEW 가 붙습니다. 같은 폴더에 덮어 풀고 확장 페이지에서 새로고침(⟳)."
        }
    }
    return ""
}

function Update-Pages {
    $mdir = Join-Path $Root 'manifest'
    $adir = Join-Path $Root 'apps'
    New-Item -ItemType Directory -Path $adir -Force | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)

    # 이전 버전 표용 릴리스 목록 (실패해도 페이지는 만든다)
    $rels = @()
    try {
        $j = gh release list -R $RepoFull --limit 500 --json tagName,publishedAt 2>$null
        if ($LASTEXITCODE -eq 0 -and $j) { $rels = @(($j -join "`n") | ConvertFrom-Json) }
    } catch { $rels = @() }

    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($a in Get-AllApps) {
        $mf = Join-Path $mdir "$($a.Key).json"
        if (-not (Test-Path -LiteralPath $mf)) {
            $rows.Add("| $($a.Name) | $($a.Kind) | - | 아직 없음 |")
            continue
        }
        $m = [IO.File]::ReadAllText($mf) | ConvertFrom-Json
        $file = [Uri]::UnescapeDataString(("$($m.url)" -split '/')[-1])
        $size = if ($m.size) { ' · {0:0.0}MB' -f ([double]$m.size / 1MB) } else { '' }
        $day = Format-Day $m.publishedAt
        $pLink = ''
        $pPage = ''
        if ($m.portable -and $m.portable.url) {
            $pFile = [Uri]::UnescapeDataString(("$($m.portable.url)" -split '/')[-1])
            $pSize = if ($m.portable.size) { ' · {0:0.0}MB' -f ([double]$m.portable.size / 1MB) } else { '' }
            $pLink = " · [포터블]($($m.portable.url))"
            $pPage = "## ⬇ [$pFile 받기 (포터블 · exe 하나)]($($m.portable.url))`n`n" +
                "exe 하나만 받아 아무 폴더(USB 등)에 두고 실행$pSize. 설치 · 압축 풀기 없음. 처음 실행은 몇 초 늦습니다. " +
                "포터블로 실행하면 업데이트도 포터블 exe 로 받습니다.`n`n"
        }
        $rows.Add("| [$($a.Name)](apps/$($a.Key).md) | $($a.Kind) | $($m.version) | [⬇ $file]($($m.url))$pLink |")

        $notes = "$($m.notes)".Trim()
        if (-not $notes) { $notes = '-' }
        $cur = "$($a.Key)-v$($m.version)"
        $old = @($rels | Where-Object { "$($_.tagName)" -like "$($a.Key)-v*" -and "$($_.tagName)" -ne $cur })
        $hist = if ($old.Count -gt 0) {
            "| 버전 | 날짜 |`n|---|---|`n" + (($old | ForEach-Object {
                $t = "$($_.tagName)"
                "| [$($t.Substring($a.Key.Length + 2))](https://github.com/$RepoFull/releases/tag/$t) | $(Format-Day $_.publishedAt) |"
            }) -join "`n")
        } else { '없음' }

        $md = "# $($a.Name)`n`n" +
            "## ⬇ [$file 받기]($($m.url))`n`n" +
            "$($a.Kind) · 버전 **$($m.version)**$size · $day`n`n" + $pPage +
            (Get-InstallGuide "$($m.platform)" "$($m.exe)") + "`n`n" +
            "## 바뀐 점 ($($m.version))`n`n$notes`n`n" +
            "## 이전 버전`n`n$hist`n`n" +
            "---`n[← 전체 앱 목록](../README.md)`n"
        [IO.File]::WriteAllText((Join-Path $adir "$($a.Key).md"), $md, $utf8)
    }

    # README 의 표 (<!-- apps:start --> ~ <!-- apps:end --> 사이만 바꾼다)
    $readme = Join-Path $Root 'README.md'
    $text = [IO.File]::ReadAllText($readme)
    $table = "<!-- apps:start -->`n| 앱 (누르면 앱 페이지) | 종류 | 최신 | 받기 |`n|---|---|---|---|`n" + ($rows -join "`n") + "`n<!-- apps:end -->"
    $new = [regex]::Replace($text, '(?s)<!-- apps:start -->.*?<!-- apps:end -->', { param($x) $table })
    if ($new -ne $text) { [IO.File]::WriteAllText($readme, $new, $utf8) }
}
