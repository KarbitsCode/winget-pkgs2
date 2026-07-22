@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<pkgname^> ^<version^>
  echo Example: %~nx0 Uninstaller 15.3.0.1
  exit /b 1
)

set "PKGNAME=%~1"
set "VERSION=%~2"
for /f "tokens=1,2,3 delims=." %%A in ("%VERSION%") do set "SHORT_VERSION=%%A.%%B.%%C"

for /f "usebackq delims=" %%A in (`
  wingetcreate show IObit.%PKGNAME% ^| powershell -NoLogo -Command ^
    "$text = $input | Out-String;" ^
    "if ($text -match 'Architecture:\s*(\S+)') { Write-Output ('ARCH=' + $matches[1]) };" ^
    "if ($text -match 'InstallerUrl:\s*(\S+)') { Write-Output ('URL=' + $matches[1]) }" ^
    "if ($text -match 'DisplayVersion:\s*(\S+)') { Write-Output ('DISPLAY_VERSION=' + $matches[1]) }"
`) do set "%%A"

for /f "usebackq delims=" %%B in (`
  powershell -NoLogo -Command ^
    "$url = ((('%URL%' -replace '\^\|', '|') -split ' ')[0] -split '\|')[0];" ^
    "$res = Invoke-WebRequest $url -Method Head -UseBasicParsing;" ^
    "$reldate = [datetime]::Parse($res.Headers['Last-Modified']).ToString('yyyy-MM-dd');" ^
    "Write-Output ('RELEASE_DATE=' + $reldate)"
`) do set "%%B"

set "OTHER_ARGS="
if defined DISPLAY_VERSION set "OTHER_ARGS=--display-version %SHORT_VERSION%"

wingetcreate update IObit.%PKGNAME% ^
  --version %VERSION% ^
  --release-date %RELEASE_DATE% ^
  --urls "%URL%|%ARCH%" ^
  %OTHER_ARGS%
