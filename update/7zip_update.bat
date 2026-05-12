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
  powershell -Command ^
    "$list = @(" ^
      "@{ File='7z%SHORT_VERSION%.exe'; Arch='x86' }," ^
      "@{ File='7z%SHORT_VERSION%-x64.exe'; Arch='x64' }," ^
      "@{ File='7z%SHORT_VERSION%-arm.exe'; Arch='arm' }," ^
      "@{ File='7z%SHORT_VERSION%-arm64.exe'; Arch='arm64' }," ^
      "@{ File='7z%SHORT_VERSION%.msi'; Arch='x86' }," ^
      "@{ File='7z%SHORT_VERSION%-x64.msi'; Arch='x64' }" ^
    ");" ^
    "[xml]$res = Invoke-WebRequest https://sourceforge.net/projects/sevenzip/rss?path=/7-Zip/%VERSION%;" ^
    "$remote = [System.Collections.Generic.HashSet[string]]::new();" ^
    "$res.rss.channel.item | ForEach-Object { [void]$remote.Add($(Split-Path -Path $_.title.InnerText -Leaf)) };" ^
    "foreach ($i in $list) {" ^
      "if ($remote.Contains($i.File)) {" ^
        "Write-Output ($i.File + '^|' + $i.Arch)" ^
      "}" ^
    "}"
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
  --release-notes-url https://github.com/ip7z/7zip/releases/tag/%VERSION% ^
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
    --release-notes-url https://github.com/ip7z/7zip/releases/tag/%VERSION% ^
    --urls !URLS!
)
