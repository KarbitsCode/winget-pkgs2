@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<version^>
  echo Example: %~nx0 26.00
  exit /b 1
)

set "VERSION=%~1"
set "SHORT_VERSION=%VERSION:.=%"

komac update 7zip.7zip ^
  --output . ^
  --skip-pr-check ^
  --version %VERSION% ^
  --release-notes-url https://github.com/ip7z/7zip/releases/tag/%VERSION% ^
  --urls ^
    "https://7-zip.org/a/7z%SHORT_VERSION%.exe|x86" ^
    "https://7-zip.org/a/7z%SHORT_VERSION%-x64.exe|x64" ^
    "https://7-zip.org/a/7z%SHORT_VERSION%-arm.exe|arm" ^
    "https://7-zip.org/a/7z%SHORT_VERSION%-arm64.exe|arm64" ^
    "https://7-zip.org/a/7z%SHORT_VERSION%.msi|x86" ^
    "https://7-zip.org/a/7z%SHORT_VERSION%-x64.msi|x64"

if not "%ERRORLEVEL%"=="0" (
  komac update 7zip.7zip ^
    --output . ^
    --skip-pr-check ^
    --version %VERSION% ^
    --release-notes-url https://github.com/ip7z/7zip/releases/tag/%VERSION% ^
    --urls ^
      "https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%/7z%SHORT_VERSION%.exe|x86" ^
      "https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%/7z%SHORT_VERSION%-x64.exe|x64" ^
      "https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%/7z%SHORT_VERSION%-arm.exe|arm" ^
      "https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%/7z%SHORT_VERSION%-arm64.exe|arm64" ^
      "https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%/7z%SHORT_VERSION%.msi|x86" ^
      "https://sourceforge.net/projects/sevenzip/files/7-Zip/%VERSION%/7z%SHORT_VERSION%-x64.msi|x64"
)
