param(
    [Parameter(Mandatory = $false, Position = 0)]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Push-Location .\winget-pkgs\

$url = git remote get-url origin
if ($url -notmatch 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$') {
    throw "Invalid url: $url"
}
$owner = $Matches[1]
$me = gh api user --jq .login
if ($owner -ne $me) {
    throw "Owner mismatch"
}
$fork = "$owner/$($Matches[2])"
$repo = gh api "repos/$fork" | ConvertFrom-Json
$upstream = $repo.parent.full_name
$default = $repo.default_branch

# Get all branches that has PR attached
$branches = gh api "repos/$fork/branches" --paginate --jq '.[] | {name: .name, protected: .protected}' | ForEach-Object { $_ | ConvertFrom-Json }
$used = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($target in @($upstream, $fork)) {
    $prs = gh pr list --repo $target --state all --author '@me' --limit 1000 --json headRefName,headRepositoryOwner | ConvertFrom-Json
    foreach ($pr in $prs) {
        if ($pr.headRepositoryOwner.login -eq $owner -or $target -eq $fork) {
            [void]$used.Add($pr.headRefName)
        }
    }
}

# The one that doesn't
$unused = $branches | Where-Object {
    $_.name -ne $default -and -not $_.protected -and -not $used.Contains($_.name)
}

if (-not $unused) {
    Write-Host 'No unused branches found.'
    return
}

Write-Host 'Branches never used in a PR:'
$unused | ForEach-Object { Write-Host "  $($_.name)" }

if (-not $DryRun) {
    foreach ($b in $unused) {
        gh api -X DELETE "repos/$fork/git/refs/heads/$($b.name)" | Out-Null
        Write-Host "Deleted $($b.name)"
    }
}

Pop-Location
