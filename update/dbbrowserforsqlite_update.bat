@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 3.13.1
  exit /b 1
)

set "VERSION=%~1"
for /f "usebackq delims=" %%A in (`
    powershell -NoProfile -Command ^
        "$r = Invoke-RestMethod 'https://api.github.com/repos/sqlitebrowser/sqlitebrowser/releases/tags/v%VERSION%';" ^
        "$r.assets | Where-Object { $_.name -match '(win32|x86)\.(msi|exe)$' } | ForEach-Object { Write-Output ('X86=' + $_.browser_download_url) };" ^
        "$r.assets | Where-Object { $_.name -match '(win64|x64)\.(msi|exe)$' } | ForEach-Object { Write-Output ('X64=' + $_.browser_download_url) }"
`) do set "%%A"

wingetcreate update DBBrowserForSQLite.DBBrowserForSQLite ^
  --version %VERSION% ^
  --urls ^
    "%X86%|x86" ^
    "%X64%|x64"
