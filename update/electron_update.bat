@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 36.7.0
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1 delims=." %%A in ("%VERSION%") do set "SHORT_VERSION=%%A"

komac update OpenJS.Electron.%SHORT_VERSION% ^
  --output . ^
  --version %VERSION% ^
  --urls ^
    "https://github.com/electron/electron/releases/download/v%VERSION%/electron-v%VERSION%-win32-ia32.zip|x86" ^
    "https://github.com/electron/electron/releases/download/v%VERSION%/electron-v%VERSION%-win32-x64.zip|x64" ^
    "https://github.com/electron/electron/releases/download/v%VERSION%/electron-v%VERSION%-win32-arm64.zip|arm64"
