@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 11.3.1.0
  exit /b 1
)

set "VERSION=%~1"
for /f "tokens=1 delims=." %%A in ("%VERSION%") do set "SHORT_VERSION=%%A"

for /f "usebackq delims=" %%A in (`
  komac show RootsMagic.RootsMagic.%SHORT_VERSION% ^| powershell -NoLogo -Command ^
    "$input = $input | Out-String;" ^
    "$urls  = @([regex]::Matches($input, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$archs = @([regex]::Matches($input, 'Architecture:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$rnurl = @([regex]::Matches($input, 'ReleaseNotesUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$count = [Math]::Min($urls.Count, $archs.Count);" ^
    "$pairs = for ($i=0; $i -lt $count; $i++) { \""$($urls[$i])^|$($archs[$i])\"" };" ^
    "if ($pairs) { Write-Output ('URL_ARGS=' + $pairs -join ' ') };"
    "if ($rnurl) { Write-Output ('RELEASE_NOTES_URL=' + $rnurl) }"
`) do set "%%A"

for /f "usebackq delims=" %%B in (`
  powershell -NoLogo -Command ^
    "$url = ((('%URL_ARGS%' -replace '\^\|', '|') -split ' ')[0] -split '\|')[0];" ^
    "$res = Invoke-WebRequest $url -Method Head -UseBasicParsing;" ^
    "$reldate = [datetime]::Parse($res.Headers['Last-Modified']).ToString('yyyy-MM-dd');" ^
    "Write-Output ('RELEASE_DATE=' + $reldate)"
`) do set "%%B"

komac update RootsMagic.RootsMagic.%SHORT_VERSION% ^
  --output . ^
  --skip-pr-check ^
  --version %VERSION% ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --urls %URL_ARGS%
