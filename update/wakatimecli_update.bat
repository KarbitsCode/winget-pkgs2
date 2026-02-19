@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 1.139.1
  exit /b 1
)

set "VERSION=%~1"

wingetcreate update Wakatime.CLIWakatime ^
  --version %VERSION% ^
  --urls ^
    "https://github.com/wakatime/wakatime-cli/releases/download/v%VERSION%/wakatime-cli-windows-386.zip|x86" ^
    "https://github.com/wakatime/wakatime-cli/releases/download/v%VERSION%/wakatime-cli-windows-amd64.zip|x64" ^
    "https://github.com/wakatime/wakatime-cli/releases/download/v%VERSION%/wakatime-cli-windows-arm64.zip|arm64" ^
