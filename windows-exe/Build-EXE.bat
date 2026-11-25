@echo off
title Building AppleBooksWindows.exe
cd /d "%~dp0"
echo Installing PyInstaller and pywebview (one-time)...
python -m pip install --upgrade pyinstaller pywebview
echo.
echo Compiling standalone AppleBooksWindows.exe...
python -m PyInstaller --noconfirm --onefile --windowed --name "AppleBooksWindows" --add-data "index.html;." books_desktop.py
echo.
if exist "dist\AppleBooksWindows.exe" (
  echo SUCCESS! Your app is ready at: dist\AppleBooksWindows.exe
) else (
  echo Build failed. Make sure Python 3 is installed from python.org.
)
pause
