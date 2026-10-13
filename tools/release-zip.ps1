# 폴더째 배포하는 앱(HTML 앱 · 크롬 확장) 릴리스: zip → GitHub 릴리스 → manifest 갱신.
#   powershell -File release-zip.ps1 -Project <폴더> -App <앱키> -Name <이름> -Platform web|chrome
#     -VersionFile version.txt            (버전 한 줄)  또는  manifest.json  (크롬 확장 — "version" 값)
#     -Exclude ".git;dist;*.bat;*.md"     zip 에서 뺄 것 (파일 · 폴더 이름 패턴, 경로의 어느 부분이든)
#     -Include "run-app.bat"              -Exclude 에 걸려도 넣을 것
#     -Keep "a;b"                         업데이트할 때 이미 있으면 덮어쓰지 않을 파일
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Name,
    [ValidateSet('web', 'chrome')][string]$Platform = 'web',
    [string]$VersionFile = 'version.txt',
    [string]$Exclude = '.git;dist;dist-release;node_modules;*.bat;*.md',
    [string]$Include = '',
    [string]$Keep = ''
)
. (Join-Path $PSScriptRoot 'common.ps1')

$Project = (Resolve-Path -LiteralPath $Project).ProviderPath
Set-Location -LiteralPath $Project

# ---------------------------------------------------------------- 버전
$vf = Join-Path $Project $VersionFile
if (-not (Test-Path $vf)) { Fail "$VersionFile 이 없습니다." }
if ($VersionFile -like '*.json') {
    $ver = "$(([IO.File]::ReadAllText($vf) | ConvertFrom-Json).version)".Trim()
} else {
    $ver = ([IO.File]::ReadAllText($vf)).Trim()
}
if (-not $ver) { Fail "$VersionFile 에서 버전을 찾지 못했습니다." }

Step "$Name $ver 릴리스"
Assert-Gh
Assert-NewTag "$App-v$ver"

# ---------------------------------------------------------------- zip
$ex = @($Exclude -split ';' | Where-Object { $_ })
$inc = @($Include -split ';' | Where-Object { $_ })
$files = Get-ChildItem -Path $Project -Recurse -File -Force | Where-Object {
    $rel = $_.FullName.Substring($Project.Length).TrimStart('\')
    if ($inc -contains $rel) { return $true }
    foreach ($part in $rel.Split('\')) { foreach ($p in $ex) { if ($part -like $p) { return $false } } }
    if ($rel -like 'keystore*') { return $false }
    return $true
}
if (-not $files) { Fail "넣을 파일이 없습니다." }

Step "압축 중 ($(@($files).Count)개 파일)"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path (Join-Path $Project 'dist-release') -Force | Out-Null
$zip = Join-Path $Project "dist-release\$App-$ver.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
$z = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Project.Length).TrimStart('\') -replace '\\', '/'
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $z.Dispose() }

# ---------------------------------------------------------------- 올리기
$notes = Get-Notes (Join-Path $Project 'CHANGELOG.md') $ver
$keepList = @($Keep -split ';' | Where-Object { $_ })
Publish-Release -App $App -Name $Name -Platform $Platform -Version $ver -VersionCode 0 -File $zip -Notes $notes -Keep $keepList
