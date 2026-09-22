param(
    [Parameter(Position = 0)]
    [int]$Delay = 60,
    [switch]$Once
)

$targetLabels = @("Internal-Error", "Defender-Error", "SmartScreen-Error", "Installation-Error")
$login = gh api user --jq .login

while ($true) {
    # Get the latest open PR
    Push-Location .\winget-pkgs\
    $prs = gh pr list --author "@me" --state open --limit 100 --json number,labels | ConvertFrom-Json
    Pop-Location
    $targetprs = @()
    $targetlabel = $targetLabels -join "|"

    # Oldest to newest
    foreach ($pr in ($prs | Sort-Object {[int]$_.number})) {
        foreach ($prlabel in $pr.labels.name) {
            if ($prlabel -match $targetlabel) {
                $comments = gh pr view $pr.number --json comments | ConvertFrom-Json
                if (-not ($comments.comments | Where-Object { $_.author.login -eq $login -and $_.body -match "(?m)^\.except$" })) {
                    $targetprs += $pr.number
                }
                break
            }
        }
    }

    if ($targetprs.Count -gt 0) {
        powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\TriggerPipeline.ps1" @targetprs
    }

    if (-not $Once) {
        Start-Sleep -Seconds $Delay
    } else {
        break
    }
}

