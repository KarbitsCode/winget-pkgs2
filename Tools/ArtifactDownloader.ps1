param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PRNumber
)

# Prepare
$prNumber = $PRNumber.Trim() -replace '#', ''
$outTemp1 = Join-Path $env:TEMP "pipeline-verification-artifact-$prNumber.zip"
$outTemp2 = Join-Path $env:TEMP "pipeline-validation-artifact-$prNumber.zip"
Remove-Item $outTemp1 -Force -ErrorAction SilentlyContinue
Remove-Item $outTemp2 -Force -ErrorAction SilentlyContinue

# Query and get the last (recent) comment
$comments = gh api repos/microsoft/winget-pkgs/issues/$prNumber/comments | ConvertFrom-Json
$botComment = $comments | Where-Object {
                            $_.user.login -eq "wingetbot" -and
                            $_.body -match "Validation Pipeline Run\s+\S+"
                        } | Select-Object -Last 1

if ($botComment) {
    $projectId = [regex]::Match($botComment.body, "dev\.azure\.com/[^/]+/([0-9a-f\-]{36})/").Groups[1].Value
    $buildId = [regex]::Match($botComment.body, "buildId=(\d+)").Groups[1].Value
    Write-Host "Found projectId: $projectId" -ForegroundColor Yellow
    Write-Host "Found buildId: $buildId" -ForegroundColor Yellow
    
    # Download using public azure api
    Write-Host "Downloading artifacts..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri "https://dev.azure.com/shine-oss/$projectId/_apis/build/builds/$buildId/artifacts?artifactName=InstallationVerificationLogs&api-version=7.1&%24format=zip" -OutFile $outTemp1 -UseBasicParsing
        Write-Host "Downloaded to $outTemp1" -ForegroundColor Green
        explorer $outTemp1
    } catch {
        Write-Warning "Failed to download artifact: $($_.Exception.Message)"
    }
    try {
        Invoke-WebRequest -Uri "https://dev.azure.com/shine-oss/$projectId/_apis/build/builds/$buildId/artifacts?artifactName=ValidationResult&api-version=7.1&%24format=zip" -OutFile $outTemp2 -UseBasicParsing
        Write-Host "Downloaded to $outTemp2" -ForegroundColor Green
        explorer $outTemp2
    } catch {
        Write-Warning "Failed to download artifact: $($_.Exception.Message)"
    }
} else {
    $pr = gh api "repos/microsoft/winget-pkgs/pulls/$PRNumber" | ConvertFrom-Json
    $checkRuns = gh api "repos/microsoft/winget-pkgs/commits/$($pr.head.sha)/check-runs?per_page=100" | ConvertFrom-Json
    $check = $checkRuns.check_runs |
        Where-Object {
            $_.name -eq "10. Validation Completed" -and
            $_.app.slug -eq "wingetvalidator-prod"
        } | Select-Object -First 1
    if (-not $check) {
        throw "Could not find the validator check for PR #$PRNumber."
    }
    $match = [regex]::Match($check.output.text, '(?s)```json\s*(.*?)\s*```')
    if (-not $match.Success) {
        throw "Could not find JSON in the check output."
    }
    $validation = $match.Groups[1].Value | ConvertFrom-Json
    try {
        Invoke-WebRequest -Uri $validation.Artifacts.ArtifactDownloadUrl -OutFile $outTemp2 -UseBasicParsing
        Write-Host "Downloaded to $outTemp2" -ForegroundColor Green
        explorer $outTemp2
    } catch {
        throw "Failed to download artifact: $($_.Exception.Message)"
    }
}
