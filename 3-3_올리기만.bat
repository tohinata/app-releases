@echo off
rem =====================================================================
rem  This file is saved in CP949 (Korean Windows console codepage).
rem  Do NOT re-save it as UTF-8 -- the messages below will be garbled.
rem
rem  What this does: shows which commits would go up, asks once, pushes.
rem  It never commits, never rebases, never forces.
rem =====================================================================
setlocal enabledelayedexpansion
title app-releases - GitHub 에 올리기
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 goto :no_git

git rev-parse --git-dir >nul 2>nul
if errorlevel 1 goto :no_repo

git remote get-url origin >nul 2>nul
if errorlevel 1 goto :no_remote

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"
for /f "delims=" %%u in ('git remote get-url origin') do set "URL=%%u"

echo.
echo  ------------------------------------------------------------
echo   올릴 곳  : !URL!
echo   브랜치   : !BRANCH!
echo  ------------------------------------------------------------
echo.

rem 원격을 먼저 확인한다. 이걸 건너뛰면 아래 '올라갈 커밋' 목록이
rem 지난번에 본 원격 상태를 기준으로 나와서 실제와 다를 수 있다.
echo  원격 상태를 확인하는 중...
git fetch origin >nul 2>nul
if errorlevel 1 goto :fetch_warned
goto :fetch_ok

:fetch_warned
echo  (원격을 확인하지 못했습니다. 아래 목록이 실제와 다를 수 있습니다.)

:fetch_ok
echo.

rem 커밋하지 않은 변경이 있으면 알려준다.
rem push 는 커밋된 것만 올리므로, 방금 고친 파일이 그냥 남는 일이 생긴다.
set "DIRTY="
for /f "delims=" %%d in ('git status --porcelain') do set "DIRTY=1"
if defined DIRTY goto :warn_dirty
goto :list

:warn_dirty
echo  [주의] 커밋하지 않은 변경이 있습니다. 아래 파일은 올라가지 않습니다.
echo.
git status --short
echo.

:list
set "UPARG="
git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" >nul 2>nul
if errorlevel 1 set "UPARG=-u"

git rev-parse --verify "origin/!BRANCH!" >nul 2>nul
if errorlevel 1 goto :first_push

set "AHEAD=0"
for /f "delims=" %%c in ('git rev-list --count "origin/!BRANCH!..HEAD"') do set "AHEAD=%%c"
if "!AHEAD!"=="0" goto :nothing_to_push

echo  올라갈 커밋 !AHEAD!개
echo.
git log --oneline "origin/!BRANCH!..HEAD"
goto :ask

:first_push
echo  이 브랜치를 올린 적이 없습니다. 히스토리 전체를 처음 올립니다.
echo.
git log --oneline -8
goto :ask

:ask
echo.
call :ask_yn " 지금 올릴까요?"
if /i "%YN%"=="N" goto :cancel

echo.
git push !UPARG! origin !BRANCH!
if errorlevel 1 goto :push_failed

echo.
echo  ------------------------------------------------------------
echo   올렸습니다.
echo.
echo     !URL!
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 0

:nothing_to_push
echo  올릴 것이 없습니다. 원격이 이미 로컬과 같습니다.
echo.
echo  참고 - 방금 고친 내용이 있다면 아직 커밋을 안 한 것입니다.
echo         커밋은 이 파일이 하지 않습니다.
echo.
pause
endlocal
exit /b 0

:cancel
echo.
echo  취소했습니다. 아무것도 올리지 않았습니다.
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
echo   (설치 직후에는 PATH 가 아직 반영되지 않습니다)
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

:no_remote
echo.
echo  ------------------------------------------------------------
echo   올릴 곳(origin)이 설정되어 있지 않습니다.
echo.
echo   GitHub 에서 빈 저장소를 만든 뒤 한 번만 아래를 실행하세요.
echo   README 나 .gitignore 는 체크하지 마세요 - 충돌합니다.
echo.
echo     git remote add origin https://github.com/아이디/저장소.git
echo.
echo   그 다음부터는 이 파일만 실행하면 됩니다.
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 1

:push_failed
echo.
echo  ------------------------------------------------------------
echo   올리지 못했습니다. 위쪽 오류 메시지를 확인하세요.
echo.
echo   자주 나오는 원인
echo.
echo     rejected ... fetch first
echo       원격에 내 저장소에 없는 커밋이 있습니다.
echo       git pull --rebase origin !BRANCH!
echo       를 먼저 하고 다시 실행하세요.
echo       (--force 는 쓰지 마세요. 원격 것이 사라집니다)
echo.
echo     Authentication failed / 로그인 창이 반복해서 뜸
echo       Windows 자격 증명 관리자에서 github 항목을 지우고
echo       다시 실행하면 로그인 창이 새로 뜹니다.
echo.
echo     Repository not found
echo       주소가 틀렸거나 그 저장소에 권한이 없습니다.
echo       git remote -v 로 주소를 확인하세요.
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
