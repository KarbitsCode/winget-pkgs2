@echo off
setlocal EnableDelayedExpansion

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 26.01
  exit /b 1
)

set "VERSION=%~1"
set "SHORT_VERSION=%VERSION:.=%"

for /f "usebackq delims=" %%A in (`
  wingetcreate show 7zip.7zr ^| powershell -Command ^
    "$input = $input | Out-String;" ^
    "$pkver = @([regex]::Matches($input, 'PackageVersion:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })[0];" ^
    "if ($pkver) { Write-Output ('PUBLISHED_VERSION=' + $pkver) };"
`) do set "%%A"

for /f "tokens=1,2 delims=." %%A in ("%PUBLISHED_VERSION%") do (
  set /a PUBLISHED_NUM=%%A*100+%%B
)

for /f "tokens=1,2 delims=." %%A in ("%VERSION%") do (
  set /a INPUT_NUM=%%A*100+%%B
)

if %INPUT_NUM% GEQ %PUBLISHED_NUM% (
  set "BASE=https://7-zip.org/a"
) else (
  set "BASE=https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%"
)

set URL=%BASE%/7zr.exe

for /f "usebackq delims=" %%A in (`
  powershell -Command ^
    "$url = 'https://github.com/ip7z/7zip/releases/tag/%VERSION%';" ^
    "try {" ^
      "Invoke-WebRequest $url;" ^
      "Write-Output ($url)" ^
    "} catch {" ^
      "$url = 'https://7-zip.org/history.txt';" ^
      "Invoke-WebRequest $url;" ^
      "Write-Output ($url)" ^
    "}"
`) do (
  set "RELEASE_NOTES_URL=%%A"
)

komac update 7zip.7zr ^
  --output . ^
  --skip-pr-check ^
  --version %VERSION% ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --urls !URL!
