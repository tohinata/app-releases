@echo off
rem =====================================================================
rem  This file is saved in CP949 (Korean Windows console codepage).
rem  Do NOT re-save it as UTF-8 -- the messages below will be garbled.
rem
rem  What this does: commit (if anything changed) and then push, in one go.
rem    commit-push.bat                  asks for a message
rem    commit-push.bat "메시지"    uses the given message
rem  It never rebases, never forces, never discards.
rem =====================================================================
setlocal enabledelayedexpansion
title app-releases - 커밋 + GitHub 에 올리기
cd /d "%~dp0"
echo.
echo  git 상태를 확인하는 중...  (%~dp0)

where git >nul 2>nul
if errorlevel 1 goto :no_git

git --no-pager rev-parse --git-dir >nul 2>nul
if errorlevel 1 goto :no_repo

git --no-pager remote get-url origin >nul 2>nul
if errorlevel 1 goto :no_remote

for /f "delims=" %%b in ('git --no-pager rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"
for /f "delims=" %%u in ('git --no-pager remote get-url origin') do set "URL=%%u"

rem ================================================================ 1) 커밋
set "DIRTY="
for /f "delims=" %%d in ('git --no-pager status --porcelain') do set "DIRTY=1"
if not defined DIRTY goto :after_commit

echo.
echo  ------------------------------------------------------------
echo   [1/2] 커밋      브랜치 : !BRANCH!
echo  ------------------------------------------------------------
echo.
echo  바뀐 파일
echo.
git --no-pager status --short
echo.

set "MSG=%~1"
if not "!MSG!"=="" goto :have_msg

echo  커밋 메시지를 한 줄로 쓰세요. 그냥 Enter 를 치면 취소합니다.
echo    예) 무엇을 고쳤는지 한 줄로
echo.
set "MSG="
set /p "MSG=메시지 : "
if "!MSG!"=="" goto :cancel

:have_msg
echo.
call :ask_yn " 이 메시지로 커밋하고 GitHub 에 올릴까요?"
if /i "%YN%"=="N" goto :cancel

git --no-pager add -A
if errorlevel 1 goto :git_failed
git --no-pager commit -q -m "!MSG!"
if errorlevel 1 goto :commit_failed
echo.
echo  커밋했습니다.
git --no-pager log --oneline -1
set "ASKED=1"

:after_commit
rem ================================================================ 2) 올리기
echo.
echo  ------------------------------------------------------------
echo   [2/2] 올리기    !URL!
echo  ------------------------------------------------------------
echo.

set "UPARG="
git --no-pager rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" >nul 2>nul
if errorlevel 1 set "UPARG=-u"

rem 원격에 이 브랜치가 아직 없으면 처음 올리는 것
git --no-pager rev-parse --verify "origin/!BRANCH!" >nul 2>nul
if errorlevel 1 goto :do_push

set "AHEAD=0"
for /f "delims=" %%c in ('git --no-pager rev-list --count "origin/!BRANCH!..HEAD"') do set "AHEAD=%%c"
if "!AHEAD!"=="0" goto :nothing

echo  올릴 커밋 !AHEAD!개
echo.
git --no-pager log --oneline "origin/!BRANCH!..HEAD"
echo.

rem 커밋을 방금 이 파일에서 했으면 이미 물어봤으니 다시 묻지 않는다
if defined ASKED goto :do_push
call :ask_yn " 이 커밋들을 GitHub 에 올릴까요?"
if /i "%YN%"=="N" goto :cancel_push

:do_push
echo  올리는 중... 처음이면 GitHub 로그인 창이 뜰 수 있습니다.
git --no-pager push !UPARG! origin !BRANCH!
if errorlevel 1 goto :push_failed

echo.
echo  ------------------------------------------------------------
echo   커밋하고 올렸습니다.
echo     !URL!
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 0

rem =====================================================================
:nothing
echo  바뀐 것도, 올릴 커밋도 없습니다. GitHub 이 이미 최신입니다.
echo.
pause
endlocal
exit /b 0

:cancel
echo.
echo  취소했습니다. 아무것도 커밋하거나 올리지 않았습니다.
echo.
pause
endlocal
exit /b 0

:cancel_push
echo.
echo  올리지 않았습니다. 커밋은 그대로 남아 있습니다.
echo.
pause
endlocal
exit /b 0

:no_git
echo.
echo  git 을 찾지 못했습니다. https://git-scm.com/download/win 에서 설치한 뒤 다시 실행하세요.
echo.
pause
endlocal
exit /b 1

:no_repo
echo.
echo  이 폴더는 git 저장소가 아닙니다. 먼저 github-init.bat 을 한 번 실행하세요.
echo.
pause
endlocal
exit /b 1

:no_remote
echo.
echo  올릴 곳(origin)이 없습니다. 먼저 github-init.bat 을 한 번 실행하세요.
echo.
pause
endlocal
exit /b 1

:git_failed
echo.
echo  파일을 담지 못했습니다. 위 메시지를 확인하세요.
echo  .git\index.lock 이 남아 있다면 git 을 쓰는 다른 프로그램을 닫고 그 파일을 지운 뒤 다시 실행하세요.
echo.
pause
endlocal
exit /b 1

:commit_failed
echo.
echo  ------------------------------------------------------------
echo   커밋하지 못했습니다. 위 메시지를 확인하세요.
echo.
echo   "Please tell me who you are" 가 보이면 한 번만 아래를 실행하세요.
echo     git config --global user.name  "tohinata"
echo     git config --global user.email "tohinata@naver.com"
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 1

:push_failed
echo.
echo  ------------------------------------------------------------
echo   커밋은 됐지만 올리지 못했습니다. 위 메시지를 확인하세요.
echo.
echo   rejected ... fetch first
echo     GitHub 쪽에 이 PC 에 없는 커밋이 있습니다. 아래를 실행한 뒤 다시 올리세요.
echo       git pull --rebase origin !BRANCH!
echo     (--force 는 쓰지 마세요. 원격 커밋이 사라집니다)
echo.
echo   로그인 창이 반복되면 Windows 자격 증명 관리자에서 github 항목을 지우고 다시 실행하세요.
echo  ------------------------------------------------------------
echo.
pause
endlocal
exit /b 1

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
