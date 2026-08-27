@echo off
setlocal
title Tecan Growth Curve Analyzer

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap.ps1" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo  ---------------------------------------------------------------
  echo   The analyzer could not be started.
  echo.
  echo   If you see a message about scripts being disabled on this
  echo   system, your IT policy is blocking PowerShell. In that case
  echo   use "Open Offline HTML Tool.bat" instead - it needs no setup.
  echo  ---------------------------------------------------------------
  echo.
  pause
)

endlocal
