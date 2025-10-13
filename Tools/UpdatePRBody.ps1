param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BodyFile
)

$BodyFile = Join-Path -Path $(Get-Location).Path -ChildPath $BodyFile
Push-Location .\winget-pkgs\

# Get the latest open PR
$prNumber = gh pr list --author "@me" --state open --limit 1 --json number --jq ".[0].number"

if (-not $prNumber) {
    Write-Error "No open PRs found for your account."
    exit 1
}

if (-not (Test-Path $BodyFile)) {
    Write-Error "File not found: $BodyFile"
    exit 1
}

# Update PR body
gh pr edit $prNumber --body-file "$BodyFile"

Write-Host "Updated PR #$prNumber body with contents of $BodyFile" -ForegroundColor Green
Pop-Location
