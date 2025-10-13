param(
    [string]$Target,
    [string]$Type = 'sha256'
)

Write-Host $(Get-RemoteChecksum -Url $Target -Algorithm $Type).ToUpper() -ForegroundColor Yellow
