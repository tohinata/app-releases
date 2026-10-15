# 릴리스 공통 함수. release-android.ps1 / release-windows.ps1 이 불러 쓴다.
# 이 파일은 UTF-8 (BOM) 으로 저장한다 — PowerShell 5.1 이 한글을 바르게 읽도록.

$ErrorActionPreference = 'Continue'
$Owner = 'tohinata'
$RepoName = 'app-releases'
$RepoFull = "$Owner/$RepoName"
$Root = Split-Path -Parent $PSScriptRoot      # app-releases 폴더
. (Join-Path $PSScriptRoot 'pages.ps1')        # 다운로드 페이지 (README 표 · apps\*.md)

function Say([string]$m) { Write-Host "  $m" }
function Step([string]$m) { Write-Host ""; Write-Host "  ------------------------------------------------------------"; Write-Host "   $m"; Write-Host "  ------------------------------------------------------------" }
function Fail([string]$m) {
    Write-Host ""; Write-Host "  [실패] $m" -ForegroundColor Red
    Undo-VersionEdits
    Write-Host ""; exit 1
}

# 빌드 등에서 실패하면 이번에 고친 버전 파일 · CHANGELOG 를 되돌린다 (다음 실행이 깨끗하게 시작하도록).
# 배포 전 Assert-Committed 로 작업 폴더가 깨끗한 것을 확인했으므로 되돌려도 사용자 수정은 없다.
$script:UndoProject = $null
$script:UndoFiles = @()
function Set-Undo([string]$Project, [string[]]$Files) { $script:UndoProject = $Project; $script:UndoFiles = $Files }
function Clear-Undo { $script:UndoProject = $null; $script:UndoFiles = @() }
function Undo-VersionEdits {
    $p = $script:UndoProject
    if (-not $p -or -not (Test-Path (Join-Path $p '.git'))) { return }
    $files = $script:UndoFiles
    Clear-Undo
    $done = $false
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $p $f))) { continue }
        git -C $p ls-files --error-unmatch -- $f *> $null
        if ($LASTEXITCODE -eq 0) { git -C $p checkout -q -- $f 2>$null }
        else { Remove-Item -LiteralPath (Join-Path $p $f) -Force -ErrorAction SilentlyContinue }
        $done = $true
    }
    if ($done) { Write-Host "  버전 파일 · CHANGELOG 는 원래대로 되돌렸습니다. 고친 뒤 4-1 을 다시 실행하세요." }
}

# git · gh 의 출력은 UTF-8 이다. PowerShell 5.1 은 콘솔 코드페이지(CP949)로 읽어 한글이 깨지므로,
# 출력을 받아 쓰는 동안만 UTF-8 로 읽는다 (끝나면 되돌려서 배치 파일의 한글 출력은 그대로).
function Invoke-Utf8([scriptblock]$Block) {
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    try { & $Block } finally { [Console]::OutputEncoding = $old }
}

function Assert-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Fail "GitHub CLI(gh)가 없습니다.`n         winget install GitHub.cli  로 설치하고, 새 창에서  gh auth login  으로 로그인한 뒤 다시 실행하세요."
    }
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { Fail "gh 에 로그인되어 있지 않습니다.  gh auth login  을 실행한 뒤 다시 하세요." }
    gh repo view $RepoFull --json name *> $null
    if ($LASTEXITCODE -ne 0) { Fail "공개 릴리스 저장소 $RepoFull 가 없습니다. app-releases\0-1_공개저장소만들기.bat 을 먼저 한 번 실행하세요." }
}

function Assert-NewTag([string]$tag) {
    gh release view $tag -R $RepoFull *> $null
    if ($LASTEXITCODE -eq 0) { Fail "이미 올린 버전입니다 ($tag).`n         버전을 올린 뒤 (CHANGELOG.md 도 같이) 다시 실행하세요." }
}

# CHANGELOG.md 에서 이 버전 부분만 (## 0.2.0 … 다음 ## 전까지). 없으면 맨 위 절.
function Get-Notes([string]$changelog, [string]$version) {
    if (-not (Test-Path -LiteralPath $changelog)) { return "" }
    $lines = [IO.File]::ReadAllLines($changelog, [Text.Encoding]::UTF8)
    $start = -1
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^##\s' -and $lines[$i] -match [regex]::Escape($version)) { $start = $i; break }
    }
    if ($start -lt 0) {
        for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match '^##\s') { $start = $i; break } }
    }
    if ($start -lt 0) { return "" }
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = $start + 1; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^##\s') { break }
        $out.Add($lines[$i])
    }
    return ($out -join "`n").Trim()
}

# gh 릴리스를 만들고 manifest/<앱>.json 을 갱신해 올린다.
function Publish-Release {
    param(
        [string]$App, [string]$Name, [string]$Platform, [string]$Version, [long]$VersionCode,
        [string]$File, [string]$Notes, [string]$Exe = "", [string[]]$Keep = @()
    )
    $tag = "$App-v$Version"
    $asset = Split-Path -Leaf $File
    $sha = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item -LiteralPath $File).Length

    Step "GitHub 에 올리는 중 — $RepoFull  ($tag, $([Math]::Round($size / 1MB, 1))MB)"
    $notesFile = Join-Path $env:TEMP "release-notes-$App.md"
    $dl = "https://github.com/$RepoFull/releases/download/$tag/$asset"
    $body = "### ⬇ 받기: [$asset]($dl)`n`n" + $(if ($Notes) { $Notes } else { "$Name $Version" })
    [IO.File]::WriteAllText($notesFile, $body, (New-Object Text.UTF8Encoding($false)))
    gh release create $tag $File -R $RepoFull --title "$Name $Version" --notes-file $notesFile
    if ($LASTEXITCODE -ne 0) { Fail "릴리스를 만들지 못했습니다. 위 메시지를 확인하세요." }
    Remove-Item $notesFile -ErrorAction SilentlyContinue

    Step "버전 정보(manifest/$App.json) 갱신"
    git -C $Root pull --ff-only -q
    if ($LASTEXITCODE -ne 0) { Fail "app-releases 를 최신으로 받지 못했습니다 (git pull). 릴리스($tag)는 올라갔으니, 정리한 뒤 manifest 만 다시 올려야 합니다." }
    $m = [ordered]@{
        app         = $App
        name        = $Name
        platform    = $Platform
        version     = $Version
        versionCode = $VersionCode
        url         = "https://github.com/$RepoFull/releases/download/$tag/$asset"
        sha256      = $sha
        size        = $size
        notes       = $Notes
        publishedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    }
    if ($Exe) { $m.exe = $Exe }
    if ($Keep.Count -gt 0) { $m.keep = $Keep }
    $json = ConvertTo-Json -InputObject $m -Depth 4
    $mdir = Join-Path $Root 'manifest'
    New-Item -ItemType Directory -Path $mdir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mdir "$App.json"), $json, (New-Object Text.UTF8Encoding($false)))

    try { Update-Pages } catch { Say "다운로드 페이지를 만들지 못했습니다 (릴리스에는 영향 없음): $($_.Exception.Message)" }
    git -C $Root add "manifest/$App.json" README.md apps
    if ($LASTEXITCODE -ne 0) { Fail "manifest 를 git 에 담지 못했습니다." }
    git -C $Root commit -q -m "$Name $Version"
    if ($LASTEXITCODE -ne 0) {
        Fail "manifest 를 커밋하지 못했습니다 (git user.name / user.email 설정 확인).`n         app-releases 폴더에서 커밋 · push 하면 앱이 새 버전을 알게 됩니다."
    }
    git -C $Root push -q
    if ($LASTEXITCODE -ne 0) {
        Fail "릴리스는 올렸지만 manifest 를 push 하지 못했습니다.`n         app-releases 폴더에서  git pull --rebase  후  git push  하세요. (그 전까지 앱이 새 버전을 모릅니다)"
    }

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Green
    Write-Host "   올렸습니다: $Name $Version" -ForegroundColor Green
    Write-Host "   https://github.com/$RepoFull/releases/tag/$tag"
    Write-Host "   기기에서 앱을 다시 열면 몇 분 안에 업데이트를 묻습니다."
    Write-Host "  ============================================================" -ForegroundColor Green
}

# ================================================================ 버전 올리기
# 4-1_새버전배포.bat 이 이번 릴리스 버전을 정한다. 지금 버전을 이미 올렸으면 끝자리 +1 을 제안하고,
# Enter 면 그대로, 1.3.0 처럼 직접 입력하면 그 번호로. 버전 파일은 스크립트가 고친다.

function Next-Patch([string]$v) {
    $p = @($v.Split('.') | ForEach-Object { [int]("0" + ($_ -replace '\D', '')) })
    while ($p.Count -lt 3) { $p += 0 }
    $p[2] = $p[2] + 1
    return ($p[0..2] -join '.')
}

function Choose-Version([string]$App, [string]$Current) {
    $proposal = $Current
    while (Test-Tag "$App-v$proposal") { $proposal = Next-Patch $proposal }
    Write-Host ""
    if ($proposal -ne $Current) { Write-Host "  지금 버전 $Current 은(는) 이미 올렸습니다." }
    Write-Host "  이번 릴리스 버전: $proposal" -ForegroundColor Cyan
    Write-Host "  Enter = 이대로 / 다른 번호는 직접 입력 (예: 1.3.0)"
    while ($true) {
        $ans = "$(Read-Host '  버전')".Trim()
        if (-not $ans) { return $proposal }
        if ($ans -notmatch '^\d+\.\d+(\.\d+)?$') { Say "1.2.3 형식으로 입력하세요."; continue }
        if (Test-Tag "$App-v$ans") { Say "$ans 은(는) 이미 올린 버전입니다."; continue }
        return $ans
    }
}

function Test-Tag([string]$tag) {
    gh release view $tag -R $RepoFull *> $null
    return ($LASTEXITCODE -eq 0)
}

# 지난 릴리스의 manifest (없으면 $null)
function Get-PrevManifest([string]$App) {
    git -C $Root pull --ff-only -q 2>$null
    $prev = Join-Path $Root "manifest\$App.json"
    if (Test-Path $prev) { return ([IO.File]::ReadAllText($prev) | ConvertFrom-Json) }
    return $null
}

# 파일의 인코딩(BOM 유무)을 지키며 정규식으로 바꾼다
function Edit-File([string]$path, [string]$pattern, [string]$replacement) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($path)
    $new = [regex]::Replace($text, $pattern, $replacement)
    if ($new -ne $text) { [IO.File]::WriteAllText($path, $new, (New-Object Text.UTF8Encoding($bom))) }
}

# CHANGELOG.md 에 이 버전 절이 없으면, 지난 릴리스 이후 커밋 메시지로 만들어 맨 위에 넣는다
function Ensure-Changelog([string]$Project, [string]$Version, $Prev) {
    $path = Join-Path $Project 'CHANGELOG.md'
    $text = if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { "# 수정 이력`n" }
    foreach ($line in ($text -split "`n")) { if ($line -match '^##\s' -and $line -match [regex]::Escape($Version)) { return } }

    $since = if ($Prev -and $Prev.publishedAt) { @("--since=$($Prev.publishedAt)") } else { @('-n', '20') }
    $log = @(Invoke-Utf8 { git -C $Project log @since --no-merges --pretty=format:%s 2>$null } |
        Where-Object { $_ -and $_ -notmatch '릴리스 - 버전 올림' })
    $items = if ($log.Count -gt 0) { ($log | ForEach-Object { "- $_" }) -join "`n" } else { "- 수정 사항 반영" }
    $section = "## $Version — $(Get-Date -Format 'yyyy-MM-dd')`n`n$items`n`n"

    $i = $text.IndexOf("`n## ")
    $new = if ($i -ge 0) { $text.Substring(0, $i + 1) + $section + $text.Substring($i + 1) } else { $text.TrimEnd() + "`n`n" + $section }
    [IO.File]::WriteAllText($path, $new, (New-Object Text.UTF8Encoding($false)))
    Say "CHANGELOG.md 에 $Version 절을 만들었습니다 (지난 릴리스 이후 커밋 메시지)."
}

# 배포 전에: 커밋 안 한 수정이 있으면 여기서 같이 커밋한다 (변경 내역은 커밋 메시지로 만들기 때문)
function Assert-Committed([string]$Project) {
    if (-not (Test-Path (Join-Path $Project '.git'))) { return }
    $dirty = @(git -C $Project status --porcelain 2>$null | Where-Object { $_ })
    if ($dirty.Count -eq 0) { return }
    Write-Host ""
    Write-Host "  커밋하지 않은 수정이 있습니다:" -ForegroundColor Yellow
    $dirty | Select-Object -First 15 | ForEach-Object { Write-Host "    $_" }
    if ($dirty.Count -gt 15) { Write-Host "    ... 외 $($dirty.Count - 15)개" }
    Write-Host ""
    Write-Host "  먼저 커밋합니다. 커밋 메시지가 이번 업데이트 안내에 들어갑니다."
    $msg = "$(Read-Host '  커밋 메시지 (Enter = 멈춤)')".Trim()
    if (-not $msg) { Write-Host ""; Write-Host "  멈췄습니다."; Write-Host ""; exit 1 }
    git -C $Project add -A
    git -C $Project commit -q -m $msg
    if ($LASTEXITCODE -ne 0) { Fail "커밋하지 못했습니다. 위 메시지를 확인하세요." }
    Say "커밋했습니다: $msg  (GitHub 에는 배포 끝에 같이 올립니다)"
}

# 올린 뒤 버전 파일 · CHANGELOG 를 커밋하고 GitHub 에 올린다 (따로 3-1 할 필요 없음)
function Commit-Version([string]$Project, [string[]]$Files, [string]$Version) {
    if (-not (Test-Path (Join-Path $Project '.git'))) { return }
    $Files = @($Files | Where-Object { Test-Path -LiteralPath (Join-Path $Project $_) })
    foreach ($f in $Files) { git -C $Project add -- $f 2>$null }
    git -C $Project commit -q -m "$Version 릴리스 - 버전 올림" -- @Files 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    Say "버전 파일을 커밋했습니다 ($Version)."
    git -C $Project push -q 2>$null
    if ($LASTEXITCODE -eq 0) { Say "프로젝트 저장소(GitHub)에도 올렸습니다. 따로 할 일 없음." }
    else { Say "프로젝트 저장소에 올리지 못했습니다 — 3-3_올리기만.bat 으로 올리세요." }
}
