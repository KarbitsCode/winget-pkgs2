@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 36.7.0
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1 delims=." %%A in ("%VERSION%") do set "SHORT_VERSION=%%A"

for /f "usebackq delims=" %%A in (`
  powershell -NoLogo -Command ^
    "$r = Invoke-RestMethod 'https://api.github.com/repos/electron/electron/releases/tags/v%VERSION%';" ^
    "$want = @{ ia32 = 'x86'; x64 = 'x64'; arm64 = 'arm64' };" ^
    "$(foreach ($key in $want.Keys) {" ^
      "$asset = $r.assets | Where-Object { $_.name -eq \"electron-v%VERSION%-win32-$key.zip\" };" ^
      "if ($asset) { Write-Output (\"`\"$($asset.browser_download_url)|$($want.$key)`\"\") }" ^
    "}) -join ' '" 2^>con
`) do set "URLS=%%A"

komac update OpenJS.Electron.%SHORT_VERSION% ^
  --output . ^
  --dry-run ^
  --skip-pr-check ^
  --version %VERSION% ^
  --urls %URLS%
