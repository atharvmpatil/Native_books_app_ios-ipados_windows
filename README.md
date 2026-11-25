# Native_books_app_ios-ipados_windows
Bringing the Apple Books experience to Windows &amp; iPad ✨ Standalone desktop .exe, automated cloud-compiled .ipa builds, and instant local Wi-Fi sync. Cross-platform Apple Books clone for Windows (.exe) and iOS/iPadOS (.ipa) with real-time Wi-Fi library sync. Built without a Mac using GitHub Actions.



Apple Books — Windows .EXE + Native iPhone & iPad .IPA (No Mac Needed, $0)
==========================================================================

1) BUILD THE WINDOWS .EXE (on your Windows PC)
----------------------------------------------
- Open "windows-exe", install Python 3 (python.org) if needed, and double-click "Build-EXE.bat".
- Your standalone desktop app will be created at:
    windows-exe\dist\AppleBooksWindows.exe
- Opening it launches a native Windows window and shows your Wi-Fi link in the title bar.

2) BUILD THE NATIVE IPAD & IPHONE .IPA WITHOUT A MAC ($0 FREE)
--------------------------------------------------------------
- Create a free PUBLIC repository on GitHub (public repos get free macOS build minutes).
- Upload everything inside the "ios-app" folder (including the hidden ".github" folder) to that repo.
- Open the "Actions" tab on GitHub -> click "Build Native iPhone & iPad IPA" -> "Run workflow".
- In ~2 minutes, download "BooksApp-iPhone-iPad.ipa" from the Artifacts section!
- Install AltStore Classic (altstore.io) on your Windows PC using your free Apple ID,
  then open BooksApp-iPhone-iPad.ipa in AltStore on your iPhone & iPad to install it natively.
  AltStore auto-refreshes the 7-day signature over Wi-Fi whenever your Windows PC is on.

3) ZERO-EXPIRATION ALTERNATIVE (No GitHub / No AltStore needed)
---------------------------------------------------------------
- Run AppleBooksWindows.exe on Windows, open its Wi-Fi link in Safari on iPad/iPhone,
  and tap Share -> "Add to Home Screen". Same full-screen look, live Wi-Fi sync, never expires.
