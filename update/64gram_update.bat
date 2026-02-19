@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 1.1.92
  exit /b 1
)

set "VERSION=%~1"

wingetcreate update 64Gram.64Gram ^
  --version %VERSION% ^
  --urls "https://github.com/TDesktop-x64/tdesktop/releases/download/v%VERSION%/64Gram-setup-x64.%VERSION%.exe|x64"
