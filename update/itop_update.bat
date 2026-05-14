@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<pkgname^> ^<version^>
  echo Example: %~nx0 iTopVPN 7.2.0.6796
  exit /b 1
)

set "PKGNAME=%~1"
set "VERSION=%~2"

for /f "usebackq delims=" %%A in (`
  wingetcreate show iTop.%PKGNAME% ^| powershell -Command ^
    "$text = $input | Out-String;" ^
    "if ($text -match 'Architecture:\s*(\S+)') { Write-Output ('ARCH=' + $matches[1]) };" ^
    "if ($text -match 'InstallerUrl:\s*(\S+)') { Write-Output ('URL=' + $matches[1]) }"
`) do set "%%A"

for /f "usebackq delims=" %%B in (`
  powershell -Command ^
    "$url = ((('%URL%' -replace '\^\|', '|') -split ' ')[0] -split '\|')[0];" ^
    "$res = Invoke-WebRequest $url -Method Head;" ^
    "$reldate = [datetime]::Parse($res.Headers['Last-Modified']).ToString('yyyy-MM-dd');" ^
    "Write-Output ('RELEASE_DATE=' + $reldate)"
`) do set "%%B"

wingetcreate update iTop.%PKGNAME% ^
  --version %VERSION% ^
  --release-date %RELEASE_DATE% ^
  --urls "%URL%|%ARCH%"
