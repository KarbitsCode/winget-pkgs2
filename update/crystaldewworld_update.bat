@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<pkgname^> ^<version^>
  echo Example: %~nx0 CrystalMarkRetro 2.1.0
  exit /b 1
)

set "PKGNAME=%~1"
set "VERSION=%~2"
for /f "delims=." %%A in ("%PKGNAME%") do set "PKGBASE=%%A"

for /f "usebackq delims=" %%A in (`
  wingetcreate show CrystalDewWorld.%PKGNAME% ^| powershell -NoLogo -Command ^
    "$input = $input | Out-String;" ^
    "$ogurl = @([regex]::Match($input, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value });" ^
    "$suffix = if ($ogurl[0] -match '%PKGBASE%\d+(?:_\d+)*(?<Suffix>[A-Za-z]*)\.exe$') { $Matches['Suffix'] };" ^
    "$list = @(" ^
      "@{ Url='https://sourceforge.net/projects/crystalmarkretro/files/%VERSION%/CrystalMarkRetro' + $('%VERSION%' -replace '\.', '_') + $suffix + '.exe'; Arch='x86' }," ^
      "@{ Url='https://sourceforge.net/projects/crystalmarkretro/files/%VERSION%/CrystalMarkRetro' + $('%VERSION%' -replace '\.', '_') + $suffix + '.exe'; Arch='x64' }," ^
      "@{ Url='https://sourceforge.net/projects/crystalmarkretro/files/%VERSION%/CrystalMarkRetro' + $('%VERSION%' -replace '\.', '_') + $suffix + '.exe'; Arch='arm64' }" ^
    ");" ^
    "$urls  = $list | ForEach-Object { $_.Url };" ^
    "$archs = $list | ForEach-Object { $_.Arch };" ^
    "$count = [Math]::Min($urls.Count, $archs.Count);" ^
    "$pairs = for ($i=0; $i -lt $count; $i++) { \""$($urls[$i])^|$($archs[$i])\"" };" ^
    "if ($pairs) { Write-Output ('URL_ARGS=' + $pairs -join ' ') };"
`) do set "%%A"

for /f "usebackq delims=" %%B in (`
  powershell -NoLogo -Command ^
    "$url = ((('%URL_ARGS%' -replace '\^\|', '|') -split ' ')[0] -split '\|')[0];" ^
    "$res = curl.exe -s -I -L $url;" ^
    "$lastm = (($res | Select-String '^^Last-Modified:').Line -replace '^^Last-Modified:\s*', '').Trim();" ^
    "$reldate = [datetime]::Parse($lastm).ToString('yyyy-MM-dd');" ^
    "Write-Output ('RELEASE_DATE=' + $reldate)"
`) do set "%%B"

wingetcreate update CrystalDewWorld.%PKGNAME% ^
  --version %VERSION% ^
  --release-date %RELEASE_DATE% ^
  --urls %URL_ARGS%
