param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$NewTitlePrefix,
    [Parameter(Position = 1)]
    [int]$Count = 1
)

Push-Location .\winget-pkgs\

# Get the latest open PR
$prNumbers = gh pr list --author "@me" --state open --limit $Count --json number --jq ".[].number"

if (-not $prNumbers) {
    Write-Error "No open PRs found for your account."
    exit 1
}

# Oldest to newest
foreach ($prNumber in ($prNumbers | Sort-Object {[int]$_})) {
    # Fetch the original title
    $oldTitle = gh pr view $prNumber --json title --jq ".title"
    
    Write-Host "Original title: $oldTitle" -ForegroundColor Yellow
    if ($oldTitle -match "^(?<prefix>[^:]+):\s") {
        $existingPrefix = $matches["prefix"]
        Write-Host "Title already has a prefix: $existingPrefix" -ForegroundColor Yellow
        continue
    }
    
    # Edit the PR title and get the result
    gh pr edit $prNumber --title "$($NewTitlePrefix): $oldTitle"
    $newTitle = gh pr view $prNumber --json title --jq ".title"
    
    Write-Host "Updated PR #$prNumber title to: '$newTitle'" -ForegroundColor Green
}

Pop-Location
