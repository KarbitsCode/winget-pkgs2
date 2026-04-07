param(
    [Parameter(Position = 0)]
    [int]$Delay = 60
)

$targetLabel = "Internal-Error"

while ($true) {
    # Get the latest open PR
    Push-Location .\winget-pkgs\
    $prs = gh pr list --author "@me" --state open --limit 100 --json number,labels | ConvertFrom-Json
    Pop-Location
    $targetprs = @()

    # Oldest to newest
    foreach ($pr in ($prs | Sort-Object {[int]$_.number})) {
        foreach ($prlabel in $pr.labels.name) {
            if ($prlabel -contains $targetLabel) {
                $targetprs += $pr.number
            }
        }
    }

    if ($targetprs.Count -gt 0) {
      pwsh -file $(Join-Path $(Split-Path $PSCommandPath -Parent) "TriggerPipeline.ps1") $($targetprs -join ' ')
    }

    Start-Sleep -Seconds $Delay
}

