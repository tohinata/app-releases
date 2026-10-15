# 다운로드 페이지(README 표 · apps\*.md)를 다시 만들고, 지금 릴리스들의 설명 맨 위에 받기 링크를 넣는다.
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Gh
git -C $Root pull --ff-only -q 2>$null

Step "릴리스 설명 다시 쓰기 (맨 위 받기 링크 + manifest 의 바뀐 점)"
foreach ($mf in Get-ChildItem -Path (Join-Path $Root 'manifest') -Filter *.json) {
    $m = [IO.File]::ReadAllText($mf.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $tag = "$($m.app)-v$($m.version)"
    gh release view $tag -R $RepoFull --json tagName *> $null
    if ($LASTEXITCODE -ne 0) { Say "건너뜀 (릴리스 없음): $tag"; continue }
    $file = [Uri]::UnescapeDataString(("$($m.url)" -split '/')[-1])
    $notes = "$($m.notes)".Trim()
    if (-not $notes) { $notes = "$($m.name) $($m.version)" }
    $nf = Join-Path $env:TEMP "release-notes-$($m.app).md"
    [IO.File]::WriteAllText($nf, "### ⬇ 받기: [$file]($($m.url))`n`n$notes", (New-Object Text.UTF8Encoding($false)))
    gh release edit $tag -R $RepoFull --notes-file $nf | Out-Null
    Remove-Item $nf -ErrorAction SilentlyContinue
    Say "고침: $tag"
}

Step "다운로드 페이지 만들기 (README · apps\)"
Update-Pages
Say "만들었습니다. 3-1_커밋+올리기.bat 으로 올리면 GitHub 에 보입니다."
