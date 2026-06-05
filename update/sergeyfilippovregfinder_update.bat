@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 2.61.1
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1-3 delims=." %%A in ("%VERSION%") do @if "%%C"=="" (set "FILLED_VERSION=%%A.%%B.0.0") else set "FILLED_VERSION=%%A.%%B.%%C.0"

for /f "usebackq delims=" %%A in (`
  komac show SergeyFilippov.RegistryFinder ^| powershell -NoLogo -NoProfile -Command ^
    "$input = $input | Out-String;" ^
    "$rnurl = @([regex]::Matches($input, 'ReleaseNotesUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "if ($rnurl) { Write-Output ('RELEASE_NOTES_URL=' + $rnurl) }"
`) do set "%%A"

komac update SergeyFilippov.RegistryFinder ^
  --output . ^
  --skip-pr-check ^
  --version %VERSION% ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --urls ^
    "https://registry-finder.com/bin/%FILLED_VERSION%/RegistryFinderSetup%VERSION%.exe|x86" ^
    "https://registry-finder.com/bin/%FILLED_VERSION%/RegistryFinderSetup%VERSION%.exe|x64" ^
    "https://registry-finder.com/bin/%FILLED_VERSION%/RegistryFinder.zip|x86" ^
    "https://registry-finder.com/bin/%FILLED_VERSION%/RegistryFinder64.zip|x64"
