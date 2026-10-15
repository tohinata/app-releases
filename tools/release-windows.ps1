# 윈도우 프로그램 릴리스: dotnet publish → zip → GitHub 릴리스 → manifest 갱신.
#   powershell -File release-windows.ps1 -Project <폴더> -App <앱키> -Name <이름> -Csproj <상대 경로> -Exe <exe 이름>
#     -Mode folder   폴더째 (LibVLC 처럼 옆에 DLL 폴더가 필요한 프로그램)
#     -Mode single   exe 하나
#     -Keep a;b      업데이트할 때 이미 있으면 덮어쓰지 않을 파일 (사용자 데이터)
#     -Portable      (-Mode folder 일 때) exe 하나짜리 포터블 판도 같이 만들어 같은 릴리스에 올린다.
#                    포터블로 실행 중인 프로그램은 포터블 exe 로, 폴더판은 zip 으로 업데이트한다.
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Csproj,
    [Parameter(Mandatory = $true)][string]$Exe,
    [ValidateSet('folder', 'single')][string]$Mode = 'folder',
    [string]$Keep = '',
    [switch]$Portable
)
. (Join-Path $PSScriptRoot 'common.ps1')

$Project = (Resolve-Path -LiteralPath $Project).Path
Set-Location -LiteralPath $Project
$proj = Join-Path $Project $Csproj
if (-not (Test-Path $proj)) { Fail "프로젝트 파일이 없습니다: $proj" }

# ---------------------------------------------------------------- 버전
$xml = [IO.File]::ReadAllText($proj)
$ver = [regex]::Match($xml, '<Version>\s*([0-9]+\.[0-9]+\.[0-9]+)').Groups[1].Value
if (-not $ver) { Fail "$Csproj 에 <Version>1.2.3</Version> 이 없습니다." }

Assert-Gh
Assert-Committed $Project
Set-Undo $Project @(($Csproj -replace '\\', '/'), 'CHANGELOG.md')
$prevM = Get-PrevManifest $App
# 이번 릴리스 버전 정하기 (이미 올린 버전이면 끝자리 +1 제안, Enter = 그대로)
$old = $ver
$ver = Choose-Version $App $ver
if ($ver -ne $old) {
    Edit-File $proj '<Version>[^<]*</Version>' "<Version>$ver</Version>"
    Edit-File $proj '<AssemblyVersion>[^<]*</AssemblyVersion>' "<AssemblyVersion>$ver.0</AssemblyVersion>"
    Edit-File $proj '<FileVersion>[^<]*</FileVersion>' "<FileVersion>$ver.0</FileVersion>"
    Say "$Csproj 를 고쳤습니다: $ver"
}
Ensure-Changelog $Project $ver $prevM
Step "$Name $ver 릴리스"
Assert-NewTag "$App-v$ver"
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Fail ".NET SDK(dotnet)를 찾지 못했습니다." }

# ---------------------------------------------------------------- 빌드
$outDir = Join-Path $Project "dist\release\$App"
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
$pubArgs = @('publish', $proj, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', $outDir,
          '-p:DebugType=None', '-p:DebugSymbols=false')
if ($Mode -eq 'single') {
    $pubArgs += @('-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true', '-p:EnableCompressionInSingleFile=true')
}
Step "빌드 중 (dotnet publish, $Mode)"
& dotnet @pubArgs
if ($LASTEXITCODE -ne 0) { Fail "빌드에 실패했습니다. 위 오류를 확인하세요." }
if (-not (Test-Path (Join-Path $outDir $Exe))) { Fail "$Exe 가 만들어지지 않았습니다." }

# ---------------------------------------------------------------- zip
Step "압축 중"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $Project "dist\$App-$ver-win-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($outDir, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

# ---------------------------------------------------------------- 포터블 (exe 하나)
# LibVLC 처럼 옆 폴더(플러그인)가 필요한 프로그램도 되도록 IncludeAllContentForSelfExtract 로
# 폴더째 exe 안에 넣는다. 처음 실행할 때 %TEMP%\.net\<앱>\ 에 같은 구조로 풀어 쓴다.
$portableFile = ''
if ($Portable -and $Mode -eq 'folder') {
    $pDir = Join-Path $Project "dist\release\$App-portable"
    if (Test-Path $pDir) { Remove-Item $pDir -Recurse -Force }
    $pArgs = @('publish', $proj, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', $pDir,
               '-p:DebugType=None', '-p:DebugSymbols=false',
               '-p:PublishSingleFile=true', '-p:IncludeAllContentForSelfExtract=true',
               '-p:IncludeNativeLibrariesForSelfExtract=true', '-p:EnableCompressionInSingleFile=true')
    Step "포터블 빌드 중 (exe 하나)"
    & dotnet @pArgs
    if ($LASTEXITCODE -ne 0) { Fail "포터블 빌드에 실패했습니다. 위 오류를 확인하세요." }
    $pExe = Join-Path $pDir $Exe
    if (-not (Test-Path $pExe)) { Fail "포터블 $Exe 가 만들어지지 않았습니다." }
    $portableFile = Join-Path $Project "dist\$App-$ver-portable.exe"
    Copy-Item -LiteralPath $pExe -Destination $portableFile -Force
    Say ("포터블: {0} ({1:0.0}MB)" -f (Split-Path -Leaf $portableFile), ((Get-Item $portableFile).Length / 1MB))
}

# ---------------------------------------------------------------- 올리기
$notes = Get-Notes (Join-Path $Project 'CHANGELOG.md') $ver
$keepList = @($Keep -split ';' | Where-Object { $_ })
Clear-Undo   # 여기부터는 올라가므로 되돌리지 않는다
Publish-Release -App $App -Name $Name -Platform 'windows' -Version $ver -VersionCode 0 -File $zip -Notes $notes -Exe $Exe -Keep $keepList -Portable $portableFile
Commit-Version $Project @(($Csproj -replace '\\', '/'), 'CHANGELOG.md') $ver
