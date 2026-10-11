param(
    [Parameter(Position = 0)]
    [int]$Delay = 60,
    [switch]$Once
)

$targetLabels = @("Internal-Error", "Defender-Error", "SmartScreen-Error")
$login = gh api user --jq .login

while ($true) {
    # Get the latest open PR
    Push-Location .\winget-pkgs\
    $prs = gh pr list --author "@me" --state open --limit 100 --json number,labels | ConvertFrom-Json
    $targetprs = @()
    $targetlabel = $targetLabels -join "|"

    # Oldest to newest
    foreach ($pr in ($prs | Sort-Object {[int]$_.number})) {
        $comments = gh pr view $pr.number --json comments | ConvertFrom-Json
        foreach ($prlabel in $pr.labels.name) {
            if ($prlabel -match $targetlabel) {
                if (-not ($comments.comments | Where-Object { $_.author.login -eq $login -and ($_.body -split '\r?\n' | Where-Object { $_.Trim() -ceq '.except' }) })) {
                    $targetprs += $pr.number
                }
                break
            } elseif ($comments.comments | Where-Object { $_.author.login -eq $login -and ($_.body -split '\r?\n' | Where-Object { $_.Trim() -ceq '.trigger' }) }) {
                $targetprs += $pr.number
            }
        }
    }
    Pop-Location

    if ($targetprs.Count -gt 0) {
        powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\TriggerPipeline.ps1" @targetprs
    }

    if (-not $Once) {
        Start-Sleep -Seconds $Delay
    } else {
        break
    }
}

