@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<pkgname^> ^<version^>
  echo Example: %~nx0 CollectURL 3.6.0.0
  exit /b 1
)

set "PKGNAME=%~1"
set "VERSION=%~2"

for /f "usebackq delims=" %%A in (`
    wingetcreate show VovSoft.%PKGNAME% ^| powershell -NoProfile -Command ^
    "$input = $input | Out-String;" ^
    "$urls  = @([regex]::Matches($input, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$archs = @([regex]::Matches($input, 'Architecture:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$count = [Math]::Min($urls.Count, $archs.Count);" ^
    "$pairs = for ($i=0; $i -lt $count; $i++) { \""$($urls[$i])^|$($archs[$i])\"" };" ^
    "if ($pairs) { $pairs -join ' ' }"
`) do set "URL_ARGS=%%A"

wingetcreate update VovSoft.%PKGNAME% ^
  --version %VERSION% ^
  --urls %URL_ARGS%
