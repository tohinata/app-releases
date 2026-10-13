@echo off
rem =====================================================================
rem  This file is saved in CP949 (Korean Windows console codepage).
rem  Do NOT re-save it as UTF-8 -- the messages below will be garbled.
rem
rem  처음 한 번: 이 폴더를 git 저장소로 만들고, GitHub 에 공개 저장소
rem  tohinata/app-releases 를 만들어 올린다. (소스 없음 - 설치 파일과 버전 정보만)
rem =====================================================================
setlocal enabledelayedexpansion
title app-releases - 처음 올리기
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 goto :no_git
where gh >nul 2>nul
if errorlevel 1 goto :no_gh
gh auth status >nul 2>nul
if errorlevel 1 goto :no_login

if exist ".git" goto :have_repo
git init -b main >nul
if errorlevel 1 goto :failed
:have_repo

set "DIRTY="
for /f "delims=" %%d in ('git status --porcelain') do set "DIRTY=1"
if not defined DIRTY goto :committed
git add -A
git commit -q -m "app-releases 시작 - 공통 업데이터와 릴리스 도구" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CUGM4xbnMjFwmJACJKrpSD"
if errorlevel 1 goto :failed
:committed

git remote get-url origin >nul 2>nul
if not errorlevel 1 goto :push
echo  GitHub 에 공개 저장소 tohinata/app-releases 를 만듭니다...
gh repo create tohinata/app-releases --public --source . --remote origin --description "온천장(tohinata) 앱 배포용 - 설치 파일과 버전 정보"
if errorlevel 1 goto :failed

:push
git push -u origin main
if errorlevel 1 goto :failed

echo.
echo  ------------------------------------------------------------
echo   만들었습니다.  https://github.com/tohinata/app-releases
echo.
echo   이제 각 프로젝트의 release.bat 으로 새 버전을 올리면
echo   기기에서 앱을 열 때 업데이트를 묻습니다.
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 0

:no_git
echo.
echo  git 을 찾지 못했습니다. https://git-scm.com/download/win
echo.
pause
exit /b 1

:no_gh
echo.
echo  GitHub CLI(gh)가 없습니다.
echo    winget install GitHub.cli
echo  로 설치하고, 새 명령 창에서  gh auth login  으로 로그인한 뒤 다시 실행하세요.
echo.
pause
exit /b 1

:no_login
echo.
echo  gh 에 로그인되어 있지 않습니다.  gh auth login  을 실행한 뒤 다시 하세요.
echo.
pause
exit /b 1

:failed
echo.
echo  실패했습니다. 위 메시지를 확인하세요.
echo.
pause
exit /b 1
