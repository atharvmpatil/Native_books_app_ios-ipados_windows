@echo off
title Building AppleBooksWindows.exe (with System Tray & Dark Icon)
cd /d "%~dp0"
echo Installing PyInstaller, pywebview, pystray, and pillow...
python -m pip install --upgrade pyinstaller pywebview pystray pillow
echo.
echo Compiling AppleBooksWindows.exe...
python -m PyInstaller --noconfirm --onefile --windowed --name "AppleBooksWindows" --icon "app_icon.ico" --add-data "index.html;." --add-data "app_icon.ico;." books_desktop.py
echo.
if exist "dist\AppleBooksWindows.exe" (
  echo SUCCESS! Your app is ready at: dist\AppleBooksWindows.exe
  echo Double-click Enable-AutoStart-Windows.bat to auto-start in the System Tray when Windows boots!
) else (
  echo Build failed. Make sure Python 3 is installed from python.org.
)
pause
