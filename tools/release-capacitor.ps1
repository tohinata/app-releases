# Capacitor(웹앱 + 안드로이드) 릴리스: vite build → cap sync → 배포용 APK(서명) → GitHub 릴리스 → manifest 갱신.
#   powershell -File release-capacitor.ps1 -Project <폴더> -App <앱키> -Name <이름>
# 버전은 android\app\build.gradle 의 versionCode / versionName.
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Name
)
. (Join-Path $PSScriptRoot 'common.ps1')

$Project = (Resolve-Path -LiteralPath $Project).ProviderPath
Set-Location -LiteralPath $Project
$folder = Split-Path -Leaf $Project
$android = Join-Path $Project 'android'

# ---------------------------------------------------------------- 버전
$gradle = [IO.File]::ReadAllText((Join-Path $android 'app\build.gradle'))
$vc = [regex]::Match($gradle, 'versionCode\s+(\d+)').Groups[1].Value
$vn = [regex]::Match($gradle, 'versionName\s+"([^"]+)"').Groups[1].Value
if (-not $vc -or -not $vn) { Fail "android\app\build.gradle 에서 versionCode / versionName 을 찾지 못했습니다." }

Step "$Name $vn ($vc) 릴리스"
Assert-Gh
Assert-NewTag "$App-v$vn"
git -C $Root pull --ff-only -q 2>$null   # 지난 릴리스 정보를 최신으로
$prev = Join-Path $Root "manifest\$App.json"
if (Test-Path $prev) {
    $pvc = [long](([IO.File]::ReadAllText($prev) | ConvertFrom-Json).versionCode)
    if ([long]$vc -le $pvc) { Fail "versionCode($vc)가 지난 릴리스($pvc)보다 커야 기기가 업데이트를 받습니다. android\app\build.gradle 에서 올리세요." }
}

# ---------------------------------------------------------------- 도구
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Fail "Node.js(npm)를 찾지 못했습니다." }
$sdk = $null
foreach ($c in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    if ($c -and (Test-Path (Join-Path $c 'platforms'))) { $sdk = $c; break }
}
if (-not $sdk) { Fail "Android SDK 를 찾지 못했습니다. Android Studio 를 설치하고 한 번 실행하세요." }
if (-not (Test-Path (Join-Path $android 'local.properties'))) {
    [IO.File]::WriteAllText((Join-Path $android 'local.properties'), "sdk.dir=$($sdk -replace '\\','/')`n")
}
if (-not ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe')))) {
    foreach ($c in @((Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'), (Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jbr'))) {
        if (Test-Path (Join-Path $c 'bin\java.exe')) { $env:JAVA_HOME = $c; break }
    }
}
if (-not ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe')))) {
    Fail "JDK 를 찾지 못했습니다. JAVA_HOME 에 Android Studio 의 jbr 폴더를 넣으세요."
}

# ---------------------------------------------------------------- 서명 키 (처음 한 번, 프로젝트 폴더에)
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
if (-not (Test-Path 'node_modules')) {
    Step "처음이라 패키지를 설치합니다 (npm install)"
    & npm install
    if ($LASTEXITCODE -ne 0) { Fail "npm install 에 실패했습니다." }
}
Step "웹 빌드 + 안드로이드 동기화 (vite build, cap sync)"
& npm run build
if ($LASTEXITCODE -ne 0) { Fail "웹 빌드에 실패했습니다." }
& npx cap sync android
if ($LASTEXITCODE -ne 0) { Fail "cap sync 에 실패했습니다." }

Step "배포용 APK 빌드 중 (assembleRelease)"
$outApk = Join-Path $android 'app\build\outputs\apk\release'
if (Test-Path $outApk) { Remove-Item $outApk -Recurse -Force }
Push-Location $android
& .\gradlew.bat assembleRelease
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "빌드에 실패했습니다. 위 오류를 확인하세요." }
$src = Get-ChildItem -Path $outApk -Filter *.apk -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $src) { Fail "APK 가 없습니다 ($outApk). 서명 설정을 확인하세요." }
if ($src.Name -like '*unsigned*') { Fail "서명되지 않은 APK 입니다. keystore.properties 와 android\app\build.gradle 의 signingConfigs 를 확인하세요." }

New-Item -ItemType Directory -Path 'dist-release' -Force | Out-Null
$out = Join-Path $Project "dist-release\$folder-$vn.apk"
Copy-Item $src.FullName $out -Force

# ---------------------------------------------------------------- 올리기
$notes = Get-Notes (Join-Path $Project 'CHANGELOG.md') $vn
Publish-Release -App $App -Name $Name -Platform 'android' -Version $vn -VersionCode ([long]$vc) -File $out -Notes $notes
