@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 1.1.92
  exit /b 1
)

set "VERSION=%~1"

for /f "usebackq delims=" %%A in (`
  powershell -NoLogo -Command ^
    "$r = Invoke-RestMethod 'https://api.github.com/repos/TDesktop-x64/tdesktop/releases/tags/v%VERSION%';" ^
    "$r.assets | Where-Object { $_.name -like '*.exe' -and $_.name -match '64Gram.*x64' } | ForEach-Object { Write-Output ('X64=' + $_.browser_download_url) }" 2^>con
`) do set "%%A"

wingetcreate update 64Gram.64Gram ^
  --version %VERSION% ^
  --urls "%X64%|x64"
