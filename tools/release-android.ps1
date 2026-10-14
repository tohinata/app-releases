# 안드로이드 앱 릴리스: 배포용 APK 빌드(서명) → GitHub 릴리스 → manifest 갱신.
#   powershell -File release-android.ps1 -Project <프로젝트 폴더> -App <앱키> -Name <이름>
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Name
)
. (Join-Path $PSScriptRoot 'common.ps1')

$Project = (Resolve-Path -LiteralPath $Project).Path
Set-Location -LiteralPath $Project
$folder = Split-Path -Leaf $Project

# ---------------------------------------------------------------- 버전
$gradle = [IO.File]::ReadAllText((Join-Path $Project 'app\build.gradle.kts'))
$vc = [regex]::Match($gradle, 'versionCode\s*=\s*(\d+)').Groups[1].Value
$vn = [regex]::Match($gradle, 'versionName\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $vc -or -not $vn) { Fail "app\build.gradle.kts 에서 versionCode / versionName 을 찾지 못했습니다." }

Assert-Gh
Assert-Committed $Project
Set-Undo $Project @('app/build.gradle.kts', 'CHANGELOG.md')
$gradleFile = Join-Path $Project 'app\build.gradle.kts'
$prevM = Get-PrevManifest $App
$pvc = if ($prevM) { [long]$prevM.versionCode } else { 0 }
# 이번 릴리스 버전 정하기 (이미 올린 버전이면 끝자리 +1 제안, Enter = 그대로)
$old = $vn
$vn = Choose-Version $App $vn
if ($vn -ne $old -or [long]$vc -le $pvc) {
    $vc = [string]([Math]::Max([long]$vc, $pvc) + 1)
    Edit-File $gradleFile 'versionCode\s*=\s*\d+' "versionCode = $vc"
    Edit-File $gradleFile 'versionName\s*=\s*"[^"]+"' "versionName = `"$vn`""
    Say "app\build.gradle.kts 를 고쳤습니다: $vn ($vc)"
}
Ensure-Changelog $Project $vn $prevM
Step "$Name $vn ($vc) 릴리스"
Assert-NewTag "$App-v$vn"

# ---------------------------------------------------------------- SDK / JDK
$sdk = $null
foreach ($c in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    if ($c -and (Test-Path (Join-Path $c 'platforms'))) { $sdk = $c; break }
}
if (-not $sdk) { Fail "Android SDK 를 찾지 못했습니다. Android Studio 를 설치하고 한 번 실행하세요." }
if (-not (Test-Path 'local.properties')) {
    [IO.File]::WriteAllText((Join-Path $Project 'local.properties'), "sdk.dir=$($sdk -replace '\\','/')`n")
}

if (-not ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe')))) {
    foreach ($c in @((Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'), (Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jbr'))) {
        if (Test-Path (Join-Path $c 'bin\java.exe')) { $env:JAVA_HOME = $c; break }
    }
}
if (-not ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe')))) {
    Fail "JDK 를 찾지 못했습니다. JAVA_HOME 에 Android Studio 의 jbr 폴더를 넣으세요."
}

# ---------------------------------------------------------------- 서명 키 (처음 한 번)
if (-not (Test-Path 'keystore.properties')) {
    Step "배포용 서명 키가 없어 새로 만듭니다 (처음 한 번)"
    New-Item -ItemType Directory -Path 'keystore' -Force | Out-Null
    $pw = 'k' + [guid]::NewGuid().ToString('N').Substring(0, 20)
    $jks = "keystore/$App-release.jks"
    & (Join-Path $env:JAVA_HOME 'bin\keytool.exe') -genkeypair -keystore $jks -storetype PKCS12 -alias $App `
        -keyalg RSA -keysize 2048 -validity 36500 -storepass $pw -keypass $pw -dname "CN=tohinata, O=coarsoft, C=KR" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "서명 키를 만들지 못했습니다." }
    [IO.File]::WriteAllText((Join-Path $Project 'keystore.properties'),
        "storeFile=$jks`nstorePassword=$pw`nkeyAlias=$App`nkeyPassword=$pw`n")
    Say "keystore\ 와 keystore.properties 를 만들었습니다. GitHub 에 올라가지 않으니 따로 백업하세요."
}

# ---------------------------------------------------------------- 빌드
Step "배포용 APK 빌드 중 (assembleRelease)"
$src = Join-Path $Project 'app\build\outputs\apk\release\app-release.apk'
if (Test-Path $src) { Remove-Item $src -Force }
& (Join-Path $Project 'gradlew.bat') assembleRelease
if ($LASTEXITCODE -ne 0) { Fail "빌드에 실패했습니다. 위 오류를 확인하세요." }
if (-not (Test-Path $src)) { Fail "APK 가 없습니다: $src  (서명 설정을 확인하세요)" }

New-Item -ItemType Directory -Path 'dist' -Force | Out-Null
$out = Join-Path $Project "dist\$folder-$vn.apk"
Copy-Item $src $out -Force

# ---------------------------------------------------------------- 올리기
$notes = Get-Notes (Join-Path $Project 'CHANGELOG.md') $vn
Clear-Undo   # 여기부터는 올라가므로 되돌리지 않는다
Publish-Release -App $App -Name $Name -Platform 'android' -Version $vn -VersionCode ([long]$vc) -File $out -Notes $notes
Commit-Version $Project @('app/build.gradle.kts', 'CHANGELOG.md') $vn
