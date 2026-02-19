@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 2.1.7
  exit /b 1
)

set "VERSION=%~1"

wingetcreate update Wakatime.DesktopWakatime ^
  --version %VERSION% ^
  --urls ^
    "https://github.com/wakatime/desktop-wakatime/releases/download/v%VERSION%/wakatime-win32-ia32.exe|x86" ^
    "https://github.com/wakatime/desktop-wakatime/releases/download/v%VERSION%/wakatime-win32-x64.exe|x64" ^
    "https://github.com/wakatime/desktop-wakatime/releases/download/v%VERSION%/wakatime-win32-arm64.exe|arm64" ^
