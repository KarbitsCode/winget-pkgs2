@echo off
setlocal EnableDelayedExpansion

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 26.00
  exit /b 1
)

set "VERSION=%~1"
set "SHORT_VERSION=%VERSION:.=%"
set "BASE=https://7-zip.org/a"

for /f "usebackq delims=" %%A in (`
  powershell -NoLogo -NoProfile -Command ^
    "$url = 'https://github.com/ip7z/7zip/releases/tag/%VERSION%';" ^
    "try {" ^
      "Invoke-WebRequest $url -Method Get -UseBasicParsing;" ^
      "Write-Output ($url)" ^
    "} catch {" ^
      "$url = 'https://7-zip.org/history.txt';" ^
      "Invoke-WebRequest $url -Method Get -UseBasicParsing;" ^
      "Write-Output ($url)" ^
    "}"
`) do (
  set "RELEASE_NOTES_URL=%%A"
)

for /f "usebackq delims=" %%A in (`
  powershell -NoLogo -NoProfile -Command ^
    "$list = @(" ^
      "@{ File='7z%SHORT_VERSION%.exe'; Arch='x86' }," ^
      "@{ File='7z%SHORT_VERSION%-x64.exe'; Arch='x64' }," ^
      "@{ File='7z%SHORT_VERSION%-arm.exe'; Arch='arm' }," ^
      "@{ File='7z%SHORT_VERSION%-arm64.exe'; Arch='arm64' }," ^
      "@{ File='7z%SHORT_VERSION%.msi'; Arch='x86' }," ^
      "@{ File='7z%SHORT_VERSION%-x64.msi'; Arch='x64' }" ^
    ");" ^
    "[xml]$res = Invoke-WebRequest https://sourceforge.net/projects/sevenzip/rss?path=/7-Zip/%VERSION% -Method Get -UseBasicParsing;" ^
    "$remote = [System.Collections.Generic.HashSet[string]]::new();" ^
    "$res.rss.channel.item | ForEach-Object { [void]$remote.Add($(Split-Path -Path $_.title.InnerText -Leaf)) };" ^
    "$list | Where-Object { $remote.Contains($_.File) } | ForEach-Object { Write-Output ($_.File + '^|' + $_.Arch) }"
`) do (
  set "FILES=!FILES! %%A"
)

for %%A in (!FILES!) do (
  for /f "tokens=1,2 delims=|" %%B in ("%%A") do (
    set "URLS=!URLS! "!BASE!/%%B^|%%C""
  )
)

komac update 7zip.7zip ^
  --output . ^
  --skip-pr-check ^
  --version %VERSION% ^
  --release-notes-url %RELEASE_NOTES_URL% ^
  --urls !URLS!

if not "%ERRORLEVEL%"=="0" (
  set "BASE=https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%"
  set "URLS="
  for %%A in (!FILES!) do (
    for /f "tokens=1,2 delims=|" %%B in ("%%A") do (
      set "URLS=!URLS! "!BASE!/%%B^|%%C""
    )
  )
  komac update 7zip.7zip ^
    --output . ^
    --skip-pr-check ^
    --version %VERSION% ^
    --release-notes-url %RELEASE_NOTES_URL% ^
    --urls !URLS!
)
