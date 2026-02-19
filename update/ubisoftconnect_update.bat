@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 169.5.0.13021
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1,2,4 delims=." %%A in ("%VERSION%") do set "SHORT_VERSION=%%A.%%B.%%C"

wingetcreate update Ubisoft.Connect ^
  --version %VERSION% ^
  --display-version %SHORT_VERSION%
