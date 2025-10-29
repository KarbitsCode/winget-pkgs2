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
    $prUrl = gh pr view $prNumber --json url --jq ".url"

    # Footer that the bot usually add to PR automatically
    $footer = "###### Microsoft Reviewers: [Open in CodeFlow](https://microsoft.github.io/open-pr/?codeflow=$prUrl)"

    # Assign footer to the given md template
    $tempFile = New-TemporaryFile
    Get-Content $BodyFile | Out-File $tempFile -Encoding utf8
    Add-Content $tempFile $footer -Encoding utf8

    # Update PR body
    gh pr edit $prNumber --body-file "$tempFile"
    Write-Host "Updated PR #$prNumber body with contents of $(Split-Path $BodyFile -Leaf)" -ForegroundColor Green

    Remove-Item $tempFile -Force
}

Pop-Location
