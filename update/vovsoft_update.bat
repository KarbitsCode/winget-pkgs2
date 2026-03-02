@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<pkgname^> ^<version^>
  echo Example: %~nx0 CollectURL 3.6.0.0
  exit /b 1
)

set "PKGNAME=%~1"
set "VERSION=%~2"

for /f "usebackq delims=" %%A in (`
    wingetcreate show VovSoft.%PKGNAME% ^| powershell -NoProfile -Command ^
    "$text = $input | Out-String;" ^
    "if ($text -match 'Architecture:\s*(\S+)') { Write-Output ('ARCH=' + $matches[1]) };" ^
    "if ($text -match 'InstallerUrl:\s*(\S+)') { Write-Output ('URL=' + $matches[1]) }"
`) do set "%%A"

wingetcreate update VovSoft.%PKGNAME% ^
  --version %VERSION% ^
  --urls "%URL%|%ARCH%" ^
