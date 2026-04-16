param(
    [Parameter(Position = 0)]
    [string]$CommitMessage = "Sync manifests"
)

$CommitMessage = $CommitMessage.Trim()
Push-Location $PSScriptRoot\..

# Check if there are changes in manifests
$changes = git status --porcelain manifests

if (-not $changes) {
    Write-Host "No changes detected in manifests folder" -ForegroundColor Yellow
    exit 0
}

# Extract package names from changed files
$changedPaths = $changes | ForEach-Object { $_.Substring(3) }
$packageFolders = $changedPaths | ForEach-Object {
    $path = $_ -replace '/$', ''
    $last = $path.Split('/')[-1]
    if ($last -match '^[0-9a-zA-Z]+(?:[.-][0-9a-zA-Z]+)*$') {
        # Has version-like format, must be directory path with version number
        if ($path -match '^manifests/(.+)/[^/]+$') {
            $matches[1] -replace '/', '.'
        }
    } elseif ($last -match '\.[a-zA-Z]{2,5}$') {
        # Has file extension, must be file path
        if ($path -match '^manifests/(.+)/[^/]+/[^/]+$') {
            $matches[1] -replace '/', '.'
        }
    } else {
        # No version or file extension, probably directory path with no version number
        if ($path -match '^manifests/(.+)$') {
            $matches[1] -replace '/', '.'
        }
    }
} | Sort-Object -Unique

if ($packageFolders.Count -le 3) {
    $branchSuffix = ($packageFolders -join "_").Substring(0, [Math]::Min(50, ($packageFolders -join "_").Length))
} else {
    $branchSuffix = "multiple-packages"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$branchTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$branchName = "sync-manifests/$branchSuffix-$branchTimestamp"

$prBody = @"
$CommitMessage ($timestamp)

"@

foreach ($pkg in $packageFolders) {
    # Strip first part ("m.Microsoft.WinDbg" -> "Microsoft.WinDbg")
    $prBody += "`n- $(($pkg -split '\.', 2)[1])"
}

$prBody += @"

<details>
<summary>Porcelain diff</summary>

``````
$(($changes -split '\r?\n' | Where-Object { $_ }) -join "`n")
``````

</details>
"@

git checkout main
git pull -v --prune
git checkout -b $branchName

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create branch"
    exit 1
}

git add manifests
git status
git commit -m $CommitMessage

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to commit changes"
    git checkout main
    git branch -D $branchName
    exit 1
}

git push -v origin $branchName

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push branch"
    git reset --mixed HEAD~1
    git checkout main
    git branch -D $branchName
    exit 1
}

$prUrl = gh pr create `
    --title $CommitMessage `
    --body $prBody `
    --base main `
    --head $branchName `
    --label "sync-manifests"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create PR"
    git checkout main
    git branch -D $branchName
    exit 1
}

git checkout main
git branch -D $branchName

Write-Host "PR successfully created at: $prUrl" -ForegroundColor Green

Pop-Location
