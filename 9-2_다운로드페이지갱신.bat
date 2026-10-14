@echo off
rem =====================================================================
rem  This file is saved in CP949 (Korean Windows console codepage).
rem  Do NOT re-save it as UTF-8 -- the messages below will be garbled.
rem
rem  다운로드 페이지(README 표, apps\앱키.md)를 다시 만들고
rem  지금 릴리스들의 설명 맨 위에 받기 링크를 넣는다. 배포할 때는 자동이라 평소엔 쓸 일 없다.
rem =====================================================================
setlocal
title app-releases - 다운로드 페이지 갱신
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\update-pages.ps1"
echo.
pause
endlocal
