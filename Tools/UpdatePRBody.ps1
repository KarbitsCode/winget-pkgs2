param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BodyFile,
    [Parameter(Position = 1)]
    [int]$Count = 1
)

$BodyFile = Join-Path -Path $(Get-Location).Path -ChildPath $BodyFile
Push-Location .\winget-pkgs\

# Get the latest open PR
$prNumbers = gh pr list --author "@me" --state open --limit $Count --json number --jq ".[].number"

if (-not $prNumbers) {
    Write-Error "No open PRs found under account."
    exit 1
}

if (-not (Test-Path $BodyFile)) {
    Write-Error "File not found: $BodyFile"
    exit 1
}

# Oldest to newest
foreach ($prNumber in ($prNumbers | Sort-Object {[int]$_})) {
    # Update PR body
    gh pr edit $prNumber --body-file "$BodyFile"
    Write-Host "Updated PR #$prNumber body with contents of $(Split-Path $BodyFile -Leaf)" -ForegroundColor Green
}

Pop-Location
