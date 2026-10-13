# 릴리스 공통 함수. release-android.ps1 / release-windows.ps1 이 불러 쓴다.
# 이 파일은 UTF-8 (BOM) 으로 저장한다 — PowerShell 5.1 이 한글을 바르게 읽도록.

$ErrorActionPreference = 'Continue'
$Owner = 'tohinata'
$RepoName = 'app-releases'
$RepoFull = "$Owner/$RepoName"
$Root = Split-Path -Parent $PSScriptRoot      # app-releases 폴더

function Say([string]$m) { Write-Host "  $m" }
function Step([string]$m) { Write-Host ""; Write-Host "  ------------------------------------------------------------"; Write-Host "   $m"; Write-Host "  ------------------------------------------------------------" }
function Fail([string]$m) { Write-Host ""; Write-Host "  [실패] $m" -ForegroundColor Red; Write-Host ""; exit 1 }

function Assert-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Fail "GitHub CLI(gh)가 없습니다.`n         winget install GitHub.cli  로 설치하고, 새 창에서  gh auth login  으로 로그인한 뒤 다시 실행하세요."
    }
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { Fail "gh 에 로그인되어 있지 않습니다.  gh auth login  을 실행한 뒤 다시 하세요." }
    gh repo view $RepoFull --json name *> $null
    if ($LASTEXITCODE -ne 0) { Fail "공개 릴리스 저장소 $RepoFull 가 없습니다. app-releases\init.bat 을 먼저 한 번 실행하세요." }
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
    [IO.File]::WriteAllText($notesFile, $(if ($Notes) { $Notes } else { "$Name $Version" }), (New-Object Text.UTF8Encoding($false)))
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

    git -C $Root add "manifest/$App.json"
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
