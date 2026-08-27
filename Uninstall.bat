@echo off
setlocal
title Remove Tecan Analyzer environment

set "TARGET=%LOCALAPPDATA%\TecanGrowthCurves"

echo.
echo  ---------------------------------------------------------------
echo   This removes the private Python environment that the analyzer
echo   installed for you:
echo.
echo      %TARGET%
echo.
echo   Your Excel files, this folder, and any other Python on this
echo   computer are NOT touched.
echo  ---------------------------------------------------------------
echo.

if not exist "%TARGET%" (
  echo  Nothing to remove - the environment is not installed.
  echo.
  pause
  endlocal
  exit /b 0
)

set "ANSWER="
set /p "ANSWER=Remove it? [y/N] "
if /i not "%ANSWER%"=="y" (
  echo.
  echo  Cancelled - nothing was removed.
  echo.
  pause
  endlocal
  exit /b 0
)

echo.
echo  Removing...
rmdir /s /q "%TARGET%"

if exist "%TARGET%" (
  echo  Could not remove everything. Close the analyzer window and try again.
) else (
  echo  Removed. Double-click "Start Tecan Analyzer.bat" to set it up again.
)

echo.
pause
endlocal
