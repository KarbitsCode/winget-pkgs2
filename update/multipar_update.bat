@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^> ^<subname^>
  echo Example: %~nx0 1.3.3.6 Beta
  exit /b 1
)

set "VERSION=%~1"

if not "%~2"=="" (
  set "SUBNAME=.%~2"
)

for /f "usebackq delims=" %%A in (`
    powershell -NoProfile -Command ^
        "$r = Invoke-RestMethod 'https://api.github.com/repos/Yutaka-Sawada/MultiPar/releases/tags/v%VERSION%';" ^
        "$r.assets | Where-Object { $_.name -match '\.(exe)$' } | ForEach-Object { Write-Output ('URL=' + $_.browser_download_url) }"
`) do set "%%A"

wingetcreate update YutakaSawada.MultiPar%SUBNAME% ^
  --version %VERSION% ^
  --urls %URL%
