@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 169.5.0.13021
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1,2,4 delims=." %%A in ("%VERSION%") do set "SHORT_VERSION=%%A.%%B.%%C"

for /f "usebackq delims=" %%A in (`
  wingetcreate show Ubisoft.Connect ^| powershell -Command ^
    "$text = $input | Out-String;" ^
    "if ($text -match 'InstallerUrl:\s*(\S+)') { Write-Output ('URL=' + $matches[1]) }"
`) do set "%%A"

for /f "usebackq delims=" %%B in (`
  powershell -Command ^
    "$res = Invoke-WebRequest %URL% -Method Head;" ^
    "$reldate = [datetime]::Parse($res.Headers['Last-Modified']).ToString('yyyy-MM-dd');" ^
    "Write-Output ('RDATE=' + $reldate)"
`) do set "%%B"

wingetcreate update Ubisoft.Connect ^
  --version %VERSION% ^
  --display-version %SHORT_VERSION% ^
  --release-date %RDATE%
