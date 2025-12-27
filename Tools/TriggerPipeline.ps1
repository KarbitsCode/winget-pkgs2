param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$PRNumbers
)

Push-Location .\winget-pkgs\
git restore .

foreach ($PRNumber in $PRNumbers) {
	$prNumber = $PRNumber -replace '#', ''
	$prInfo = gh pr view $prNumber --json title,headRepository,headRepositoryOwner,headRefName,labels | ConvertFrom-Json

	if (-not $prInfo) {
		Write-Error "Could not retrieve PR #$prNumber"
	} else {
		$prRepo = "$($prInfo.headRepositoryOwner.name)/$($prInfo.headRepository.name)"
		$prBranch = $prInfo.headRefName
		$prTitle = $prInfo.title
		if ($prInfo.labels.name -contains "Moderator-Approved") {
			# Only Reopen the PR if moderator already approved it
			Write-Host "Reopen PR on:" -ForegroundColor Yellow
			Write-Host "- branch '$prBranch'" -ForegroundColor Yellow
			Write-Host "- repo '$prRepo'" -ForegroundColor Yellow
			Write-Host "With:" -ForegroundColor Yellow
			Write-Host "- number '$prNumber'" -ForegroundColor Yellow
			Write-Host "- title '$prTitle'" -ForegroundColor Yellow

			gh pr close $prNumber
			gh pr reopen $prNumber

			Write-Host "Reopen successfully for PR #$prNumber" -ForegroundColor Green
		} else {
			# Extract the text after ':' (if present) and before 'version'
			$pattern = '^(?:.*:\s*)?([A-Za-z0-9._-]+)(?:\s+version\s+.*)?$'
			if ($prTitle -match $pattern) {
				$name = $matches[1]
				$commitMessage = "Update $name.yaml"
			} else {
				Write-Error "Wrong title format on PR #$prNumber"
				exit 1
			}

			Write-Host "Creating empty commit on:" -ForegroundColor Yellow
			Write-Host "- branch '$prBranch'" -ForegroundColor Yellow
			Write-Host "- repo '$prRepo'" -ForegroundColor Yellow
			Write-Host "For PR:" -ForegroundColor Yellow
			Write-Host "- number '$prNumber'" -ForegroundColor Yellow
			Write-Host "- title '$prTitle'" -ForegroundColor Yellow
			Write-Host "With:" -ForegroundColor Yellow
			Write-Host "- message '$commitMessage'" -ForegroundColor Yellow

			git pull -v --prune
			git fetch origin $prBranch -v
			git checkout $prBranch
			git commit --allow-empty -m "$commitMessage"
			git push origin $prBranch -v
			git checkout master
			git branch -D $prBranch

			Write-Host "Empty commit successfully pushed to PR #$prNumber" -ForegroundColor Green
		}
	}
}

Pop-Location
