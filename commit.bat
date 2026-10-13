@echo off
rem =====================================================================
rem  This file is saved in CP949 (Korean Windows console codepage).
rem  Do NOT re-save it as UTF-8 -- the messages below will be garbled.
rem
rem  What this does: shows what changed, asks for a commit message,
rem  commits everything (git add -A), then offers to run push.bat.
rem  It never amends, never rebases, never forces.
rem =====================================================================
setlocal enabledelayedexpansion
title app-releases - 커밋하기
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 goto :no_git

git rev-parse --git-dir >nul 2>nul
if errorlevel 1 goto :no_repo

rem ------------------------------------------------------------ 바뀐 것
set "DIRTY="
for /f "delims=" %%d in ('git status --porcelain') do set "DIRTY=1"
if not defined DIRTY goto :nothing

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"
set "VER="
for /f tokens^=2^ delims^=^" %%v in ('findstr /c:"versionName" app\build.gradle.kts') do set "VER=%%v"

echo.
echo  ------------------------------------------------------------
echo   브랜치 : !BRANCH!     앱 버전 : !VER!
echo  ------------------------------------------------------------
echo.
echo  바뀐 파일  - M 수정  A 추가  D 삭제  ?? 새 파일
echo.
git status --short
echo.

rem 이 저장소는 고칠 때마다 CHANGELOG 에 적는다. 빠뜨렸으면 알려준다.
set "LOGGED="
for /f "delims=" %%c in ('git status --porcelain -- CHANGELOG.md') do set "LOGGED=1"
if not defined LOGGED (
    echo  [참고] CHANGELOG.md 를 고치지 않았습니다. 기록할 내용이면 먼저 적어 두세요.
    echo.
)

rem ------------------------------------------------------------ 메시지
echo  커밋 메시지를 입력하세요. 비워 두고 Enter 를 누르면 취소합니다.
echo    예 - !VER! - 자막 목록 북마크
echo.
set "TITLE="
set /p "TITLE= 제목 : "
if not defined TITLE goto :cancel
set TITLE=!TITLE:"=!
if "!TITLE!"=="" goto :cancel

set "BODY="
set /p "BODY= 설명 (없으면 Enter) : "
if defined BODY set BODY=!BODY:"=!

echo.
echo  ------------------------------------------------------------
echo   제목 : !TITLE!
if defined BODY echo   설명 : !BODY!
echo  ------------------------------------------------------------
echo.
call :ask_yn " 위 파일을 모두 이 메시지로 커밋할까요?"
if /i "%YN%"=="N" goto :cancel

git add -A
if errorlevel 1 goto :commit_failed
if defined BODY (
    git commit -q -m "!TITLE!" -m "!BODY!"
) else (
    git commit -q -m "!TITLE!"
)
if errorlevel 1 goto :commit_failed

echo.
echo  커밋했습니다.
echo.
git log --oneline -1
echo.

rem ------------------------------------------------------------ 이어서 올리기
if not exist "push.bat" goto :done
call :ask_yn " 이어서 GitHub 에 올릴까요? push.bat 을 실행합니다."
if /i "%YN%"=="N" goto :done
endlocal
call push.bat
exit /b %errorlevel%

:done
echo.
echo  GitHub 에 올리려면 push.bat 을 실행하세요.
echo.
pause
endlocal
exit /b 0

rem =====================================================================
:nothing
echo.
echo  커밋할 변경이 없습니다. 작업 폴더가 마지막 커밋과 같습니다.
echo.
pause
endlocal
exit /b 0

:cancel
echo.
echo  취소했습니다. 아무것도 커밋하지 않았습니다.
echo.
pause
endlocal
exit /b 0

:no_git
echo.
echo  ------------------------------------------------------------
echo   git 을 찾지 못했습니다.
echo.
echo   https://git-scm.com/download/win 에서 받아 설치한 뒤
echo   창을 새로 열고 다시 실행하세요.
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 1

:no_repo
echo.
echo  ------------------------------------------------------------
echo   이 폴더는 git 저장소가 아닙니다.
echo.
echo   이 파일은 저장소 폴더 안에 두고 실행해야 합니다.
echo   지금 위치 : %~dp0
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 1

:commit_failed
echo.
echo  ------------------------------------------------------------
echo   커밋하지 못했습니다. 위쪽 오류 메시지를 확인하세요.
echo.
echo   자주 나오는 원인
echo.
echo     Please tell me who you are
echo       이 PC 에서 git 사용자 이름과 이메일을 정한 적이 없습니다.
echo       한 번만 아래를 실행하고 다시 해 보세요.
echo         git config --global user.name  "이름"
echo         git config --global user.email "메일주소"
echo.
echo     index.lock ... File exists
echo       다른 git 작업(Android Studio 등)이 도는 중입니다.
echo       끝난 뒤 다시 실행하세요.
echo.
echo   add 까지 된 경우 파일은 스테이지에 올라가 있습니다.
echo   git status 로 확인할 수 있습니다.
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 1

exit /b

rem =====================================================================
rem  Y/N 묻기. choice 는 한글 입력 상태에서 누른 ㅛ / ㅜ 를 받지 못해서 set /p 로 직접 받는다.
rem    call :ask_yn "물어볼 말"   ->  YN 이 Y 또는 N
rem =====================================================================
:ask_yn
set "YN="
set "ANS="
set /p "ANS=%~1 (Y/N) : "
if /i "%ANS%"=="y" set "YN=Y"
if /i "%ANS%"=="yes" set "YN=Y"
if "%ANS%"=="ㅛ" set "YN=Y"
if /i "%ANS%"=="n" set "YN=N"
if /i "%ANS%"=="no" set "YN=N"
if "%ANS%"=="ㅜ" set "YN=N"
if defined YN exit /b 0
echo   Y 또는 N 을 입력하고 Enter 를 누르세요. (한글 상태의 ㅛ / ㅜ 도 됩니다)
goto :ask_yn
