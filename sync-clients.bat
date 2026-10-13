@echo off
rem =====================================================================
rem  This file is saved in CP949 (Korean Windows console codepage).
rem  Do NOT re-save it as UTF-8 -- the messages below will be garbled.
rem
rem  client\ 의 공통 업데이터 원본을 모든 앱 프로젝트에 복사한다 (앱 목록: tools\apps.ps1).
rem =====================================================================
setlocal
title app-releases - 공통 업데이터 복사
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\sync-clients.ps1"
echo.
echo  복사했습니다. 각 프로젝트를 빌드해 확인하세요.
echo.
pause
endlocal
