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
  wingetcreate show VovSoft.%PKGNAME% ^| powershell -Command ^
    "$input = $input | Out-String;" ^
    "$urls  = @([regex]::Matches($input, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$archs = @([regex]::Matches($input, 'Architecture:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$count = [Math]::Min($urls.Count, $archs.Count);" ^
    "$pairs = for ($i=0; $i -lt $count; $i++) { \""$($urls[$i])^|$($archs[$i])\"" };" ^
    "if ($pairs) { Write-Output ('URL_ARGS=' + $pairs -join ' ') }"
`) do set "%%A"

for /f "usebackq delims=" %%B in (`
  powershell -Command ^
    "$url = ((('%URL_ARGS%' -replace '\^\|', '|') -split ' ')[0] -split '\|')[0];" ^
    "$res = Invoke-WebRequest $url -Method Head;" ^
    "$reldate = [datetime]::Parse($res.Headers['Last-Modified']).ToString('yyyy-MM-dd');" ^
    "Write-Output ('RELEASE_DATE=' + $reldate)"
`) do set "%%B"

for /f "usebackq delims=" %%C in (`
  wingetcreate show VovSoft.%PKGNAME% ^| powershell -Command ^
    "$text = $input | Out-String;" ^
    "if ($text -match 'ReleaseNotesUrl:\s*(\S+)') { Write-Output ('RELEASE_NOTES_URL=' + $matches[1]) }"
`) do set "%%C"

wingetcreate update VovSoft.%PKGNAME% ^
  --version %VERSION% ^
  --release-date %RELEASE_DATE% ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --urls %URL_ARGS%
