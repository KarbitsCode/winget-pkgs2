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
$changedPaths = $changes | ForEach-Object {
    $path = $_.Substring(3)
    # For renamed files, "R  old -> new"
    if ($path -match '^\s*(.+?)\s+->\s+(.+?)\s*$') {
        $path = $matches[2]
    }
    Write-Output $path
}
$packageFolders = $changedPaths | ForEach-Object {
    $path = $_ -replace '/$', ''
    $last = $path.Split('/')[-1]
    if ($last -match '\.[a-zA-Z]{2,5}$') {
        # Has file extension, must be file path
        if ($path -match '^manifests/(.+)/[^/]+/[^/]+$') {
            $matches[1] -replace '/', '.'
        }
    } elseif ($last -match '^[0-9a-zA-Z]+([.-][0-9a-zA-Z]+)*$' -and $last -match '[0-9]') {
        # Has version-like format, must be directory path with version number
        if ($path -match '^manifests/(.+)/[^/]+$') {
            $matches[1] -replace '/', '.'
        }
    } else {
        # No version or file extension, probably directory path with nothing else
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

$prBodyFile = New-TemporaryFile
Set-Content -Path $prBodyFile -Value $prBody -Encoding UTF8

git checkout main
git pull -v --prune
git push -v
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

try {
    $prUrl = gh pr create `
        --title $CommitMessage `
        --body-file $prBodyFile `
        --base main `
        --head $branchName `
        --label "sync-manifests"

    if ($LASTEXITCODE -ne 0) {
        throw $prUrl
    }
} catch {
    Write-Error "Failed to create PR: $($_.Exception)"
    git checkout main
    git branch -D $branchName
    exit 1
}

git checkout main
git branch -D $branchName
Remove-Item $prBodyFile -Force

Write-Host "PR successfully created at: $prUrl" -ForegroundColor Green

Pop-Location
