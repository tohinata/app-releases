# client\ 의 공통 업데이터 원본을 모든 앱 프로젝트에 복사한다.
. (Join-Path $PSScriptRoot 'apps.ps1')
$Root = Split-Path -Parent $PSScriptRoot
$Repos = Split-Path -Parent $Root
$kt = [IO.File]::ReadAllText((Join-Path $Root 'client\android\AppUpdater.kt'), [Text.Encoding]::UTF8)
$cs = [IO.File]::ReadAllBytes((Join-Path $Root 'client\windows\AppUpdater.cs'))
$utf8 = New-Object Text.UTF8Encoding($false)

foreach ($a in $AndroidApps) {
    $proj = Join-Path $Repos $a.Folder
    if (-not (Test-Path $proj)) { Write-Host "  건너뜀 (폴더 없음): $($a.Folder)"; continue }
    $dir = Join-Path $proj ('app\src\main\java\' + ($a.Package -replace '\.', '\') + '\update')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'AppUpdater.kt'), $kt.Replace('__PACKAGE__', $a.Package), $utf8)
    Write-Host "  복사: $($a.Folder)"
}
foreach ($a in $WindowsApps) {
    $proj = Join-Path $Repos $a.Folder
    if (-not (Test-Path $proj)) { Write-Host "  건너뜀 (폴더 없음): $($a.Folder)"; continue }
    $dst = Join-Path $proj $a.Target
    New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
    [IO.File]::WriteAllBytes($dst, $cs)
    Write-Host "  복사: $($a.Folder)"
}

$ja = [IO.File]::ReadAllText((Join-Path $Root 'client\android-java\AppUpdater.java'), [Text.Encoding]::UTF8)
$jr = [IO.File]::ReadAllText((Join-Path $Root 'client\android-java\UpdateReceiver.java'), [Text.Encoding]::UTF8)
foreach ($a in $JavaApps) {
    $proj = Join-Path $Repos $a.Folder
    if (-not (Test-Path $proj)) { Write-Host "  건너뜀 (폴더 없음): $($a.Folder)"; continue }
    $dir = Join-Path $proj ('android\app\src\main\java\' + ($a.Package -replace '\.', '\') + '\update')
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'AppUpdater.java'), $ja.Replace('__PACKAGE__', $a.Package), $utf8)
    [IO.File]::WriteAllText((Join-Path $dir 'UpdateReceiver.java'), $jr.Replace('__PACKAGE__', $a.Package), $utf8)
    Write-Host "  복사: $($a.Folder)"
}
$web = [IO.File]::ReadAllBytes((Join-Path $Root 'client\web\update.ps1'))
foreach ($a in $WebApps) {
    $proj = Join-Path $Repos $a.Folder
    if (-not (Test-Path $proj)) { Write-Host "  건너뜀 (폴더 없음): $($a.Folder)"; continue }
    [IO.File]::WriteAllBytes((Join-Path $proj 'update.ps1'), $web)
    Write-Host "  복사: $($a.Folder)"
}
$js = [IO.File]::ReadAllText((Join-Path $Root 'client\chrome\update-check.js'), [Text.Encoding]::UTF8)
foreach ($a in $ChromeApps) {
    $proj = Join-Path $Repos $a.Folder
    if (-not (Test-Path $proj)) { Write-Host "  건너뜀 (폴더 없음): $($a.Folder)"; continue }
    [IO.File]::WriteAllText((Join-Path $proj 'update-check.js'), $js.Replace('__APP__', $a.Key), $utf8)
    Write-Host "  복사: $($a.Folder)"
}
