param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$PRNumbers
)

# Prepare
$prNumber = $PRNumbers -replace '#', ''
$outTemp = Join-Path $env:TEMP "pipeline-artifact-$prNumber.zip"
Remove-Item $outTemp -Force -ErrorAction SilentlyContinue

# Query and get the last (recent) comment
$comments = gh api repos/microsoft/winget-pkgs/issues/$prNumber/comments | ConvertFrom-Json
$botComment = $comments | Where-Object {
							$_.user.login -eq "wingetbot" -and
							$_.body -match "Validation Pipeline Run\s+\S+"
						} | Select-Object -Last 1

if (-not $botComment) {
	throw "No matching bot comment found."
}

# Extract projectId and buildId (the most important)
$projectId = [regex]::Match($botComment.body, "dev\.azure\.com/[^/]+/([0-9a-f\-]{36})/").Groups[1].Value
$buildId = [regex]::Match($botComment.body, "buildId=(\d+)").Groups[1].Value
Write-Host "Found projectId: $projectId" -ForegroundColor Yellow
Write-Host "Found buildId: $buildId" -ForegroundColor Yellow

# Download using public azure api
Write-Host "Downloading artifacts..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "https://dev.azure.com/shine-oss/$projectId/_apis/build/builds/$buildId/artifacts?artifactName=InstallationVerificationLogs&api-version=7.1&%24format=zip" -OutFile $outTemp
Write-Host "Downloaded to $outTemp" -ForegroundColor Green
explorer $outTemp
