@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 3.14.1.6
  exit /b 1
)

set "VERSION=%~1"

komac update Chill-Astro.TMM ^
  --output . ^
  --dry-run ^
  --skip-pr-check ^
  --version %VERSION% ^
  --urls ^
    "https://github.com/Chill-Astro/Trust-My-Msix/releases/download/v%VERSION%/Setup.exe|x64" ^
    "https://github.com/Chill-Astro/Trust-My-Msix/releases/download/v%VERSION%/tmm.exe|x64"
