param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,
    [Parameter(Mandatory = $false, Position = 1)]
    [string]$ManifestVersion
)

if (-not $ManifestVersion) {
    $ManifestVersion = (
        Invoke-RestMethod "https://github.com/microsoft/winget-cli/raw/refs/heads/master/schemas/JSON/manifests/latest/manifest.version.latest.json"
    ).properties.ManifestVersion.default
}

Get-ChildItem -Path $Path -Recurse -Filter *.yaml | ForEach-Object {
    $content = Get-Content $_.FullName -Raw

    $content = $content -replace '(?m)(?<=^# yaml-language-server: \$schema=https://aka\.ms/winget-manifest\.[^.]+\.)\d+\.\d+\.\d+(?=\.schema\.json)', $ManifestVersion
    $content = $content -replace "(?m)^ManifestVersion:\s*.*$", "ManifestVersion: $ManifestVersion"

    Set-Content -Path $_.FullName -Value $content -NoNewline
}
