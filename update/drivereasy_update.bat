@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 7.2.0.6141
  exit /b 1
)

set "VERSION=%~1"

for /f "usebackq delims=" %%A in (`
  komac show Easeware.DriverEasy ^| powershell -NoLogo -Command ^
    "$text = $input | Out-String;" ^
    "if ($text -match 'Architecture:\s*(\S+)') { Write-Output ('ARCH=' + $matches[1]) };" ^
    "if ($text -match 'InstallerUrl:\s*(\S+)') { Write-Output ('URL=' + $matches[1]) };" ^
    "if ($text -match 'ReleaseNotesUrl:\s*(\S+)') { Write-Output ('RELEASE_NOTES_URL=' + $matches[1]) }" 2^>con
`) do set "%%A"

komac update Easeware.DriverEasy ^
  --output . ^
  --dry-run ^
  --skip-pr-check ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --version %VERSION% ^
  --urls "%URL%|%ARCH%"
