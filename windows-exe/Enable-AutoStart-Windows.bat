@echo off
title Enable Automatic Wi-Fi Sync on Windows Startup
cd /d "%~dp0"
set "EXE_PATH=%~dp0dist\AppleBooksWindows.exe"
if not exist "%EXE_PATH%" (
  echo Please run Build-EXE.bat first to create dist\AppleBooksWindows.exe!
  pause
  exit /b 1
)
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\AppleBooksSync.vbs"
echo Set WshShell = CreateObject("WScript.Shell") > "%STARTUP%"
echo WshShell.Run """%EXE_PATH%"" --background", 0, False >> "%STARTUP%"
echo.
echo Done! Apple Books Wi-Fi Sync will now start silently every time your Windows laptop turns on.
echo Starting background sync right now...
wscript "%STARTUP%"
pause
