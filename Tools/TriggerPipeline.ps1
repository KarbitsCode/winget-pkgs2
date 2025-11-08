param(
    [Parameter(Mandatory = $true, Position = 0)]
    [int]$PRNumber
)

Push-Location .\winget-pkgs\

$prInfo = gh pr view $PRNumber --json title,headRepository,headRepositoryOwner,headRefName | ConvertFrom-Json

if (-not $prInfo) {
    Write-Error "Could not retrieve PR #$PRNumber"
    exit 1
}

$prRepo = "$($prInfo.headRepositoryOwner.name)/$($prInfo.headRepository.name)"
$prBranch = $prInfo.headRefName
$prTitle = $prInfo.title

# Extract the text after ':' (if present) and before 'version'
$pattern = '(?::\s*)?([A-Za-z0-9\.\-_]+)(?:\s+version.*)?$'
if ($prTitle -match $pattern) {
    $name = $matches[1]
    $commitMessage = "Update $name.yaml"
} else {
    Write-Error "Wrong title format on PR #$PRNumber"
    exit 1
}

Write-Host "Creating empty commit on:" -ForegroundColor Yellow
Write-Host "- branch '$prBranch'" -ForegroundColor Yellow
Write-Host "- repo '$prRepo'" -ForegroundColor Yellow
Write-Host "For PR:" -ForegroundColor Yellow
Write-Host "- number '$PRNumber'" -ForegroundColor Yellow
Write-Host "- title '$prTitle'" -ForegroundColor Yellow
Write-Host "With:" -ForegroundColor Yellow
Write-Host "- message '$commitMessage'" -ForegroundColor Yellow

git restore .
git pull -v --prune
git fetch origin $prBranch -v
git checkout $prBranch
git commit --allow-empty -m "$commitMessage"
git push origin $prBranch -v
git checkout master
git branch -D $prBranch

Pop-Location
Write-Host "Empty commit successfully pushed to PR #$PRNumber" -ForegroundColor Green
Pop-Location
