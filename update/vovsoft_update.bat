@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<pkgname^> ^<version^>
  echo Example: %~nx0 CollectURL 3.6.0.0
  exit /b 1
)

set "PKGNAME=%~1"
set "VERSION=%~2"

wingetcreate update VovSoft.%PKGNAME% ^
  --version %VERSION% ^
