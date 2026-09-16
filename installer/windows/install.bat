@echo off
rem ---------------------------------------------------------------------
rem  ZShare -- install, or remove, for every game and every route.
rem
rem  This only starts install.ps1, which does the work. It exists because
rem  Windows opens a .ps1 in Notepad when it is double-clicked, and a
rem  .bat it runs.
rem
rem      install.bat               show what it will do, ask once, copy
rem      install.bat -Yes          copy without asking
rem      install.bat -Uninstall    remove what an install put there
rem      install.bat -Find         show what it detects, change nothing
rem ---------------------------------------------------------------------
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "CODE=%ERRORLEVEL%"

rem Keep the window open when it was double-clicked, so the result can be
rem read. A flag means it was run from a prompt or a script, which has its
rem own window.
if "%~1"=="" pause

exit /b %CODE%
