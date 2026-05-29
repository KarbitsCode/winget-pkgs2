@echo off
setlocal EnableDelayedExpansion

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 2.61.1
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1-3 delims=." %%A in ("%VERSION%") do if "%%C"=="" (set "FILLED_VERSION=%%A.%%B.0")

for /f "usebackq delims=" %%A in (`
  komac show SergeyFilippov.RegistryFinder ^| powershell -Command ^
    "$input = $input | Out-String;" ^
    "$rnurl = @([regex]::Matches($input, 'ReleaseNotesUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "if ($rnurl) { Write-Output ('RELEASE_NOTES_URL=' + $rnurl) }"
`) do set "%%A"

for /f "usebackq delims=" %%A in (`
  powershell -Command ^
    "$list = @(" ^
      "@{ Url='https://registry-finder.com/bin/%FILLED_VERSION%.0/RegistryFinderSetup%VERSION%.exe'; Arch='x86' }," ^
      "@{ Url='https://registry-finder.com/bin/%FILLED_VERSION%.0/RegistryFinderSetup%VERSION%.exe'; Arch='x64' }," ^
      "@{ Url='https://registry-finder.com/bin/%FILLED_VERSION%.0/RegistryFinder.zip'; Arch='x86' }," ^
      "@{ Url='https://registry-finder.com/bin/%FILLED_VERSION%.0/RegistryFinder64.zip'; Arch='x64' }" ^
    ");" ^
    "if ($list) { $list | ForEach-Object { Write-Output ($_.Url + '^|' + $_.Arch) } }"
`) do set "URLS=!URLS! ^"%%A^""

komac update SergeyFilippov.RegistryFinder ^
  --output . ^
  --skip-pr-check ^
  --version %VERSION% ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --urls %URLS%
