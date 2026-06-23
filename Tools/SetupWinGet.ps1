function Get-GitHubRateLimit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        $Headers
    )
    function Get-FromHeaders {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            $h
        )
        if (-not $h["X-RateLimit-Limit"]) {
            return $null
        }
        $limit     = $h["X-RateLimit-Limit"]
        $remaining = $h["X-RateLimit-Remaining"]
        $reset     = $h["X-RateLimit-Reset"]
        if ($limit     -is [array]) { $limit     = $limit[0] }
        if ($remaining -is [array]) { $remaining = $remaining[0] }
        if ($reset     -is [array]) { $reset     = $reset[0] }
        $limit     = [int]$limit
        $remaining = [int]$remaining
        $resetTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$reset).LocalDateTime
        $currTime  = [DateTimeOffset]::Now.LocalDateTime
        $info = [PSCustomObject]@{
            Limit     = $limit
            Remaining = $remaining
            Reset     = $resetTime
            Current   = $currTime
        }
        return $info
    }
    if ($Headers) {
        $info = Get-FromHeaders $Headers
    }
    if (-not $info) {
        $r = Invoke-WebRequest -Uri "https://api.github.com/rate_limit" -UseBasicParsing
        $rate = ($r.Content | ConvertFrom-Json).resources.core
        $limit     = [int]$rate.limit
        $remaining = [int]$rate.remaining
        $resetTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$rate.reset).LocalDateTime
        $currTime  = [DateTimeOffset]::Now.LocalDateTime
        $info = [PSCustomObject]@{
            Limit     = $limit
            Remaining = $remaining
            Reset     = $resetTime
            Current   = $currTime
        }
    }
    $percent = [Math]::Round(($info.Remaining / $info.Limit) * 100, 1)
    Write-Warning "GitHub API rate limit: $($info.Remaining) / $($info.Limit) remaining ($percent%) - resets at $($info.Reset) (now $($info.Current))"
}

function Get-ReleaseTag {
    [CmdletBinding()]
    param()
    try {
        $response  = Invoke-WebRequest -Uri "https://api.github.com/repos/microsoft/winget-cli/releases?per_page=100" -UseBasicParsing
        $releasesAPIResponse = $response.Content | ConvertFrom-Json
        Get-GitHubRateLimit $response.Headers
    } catch {
        $iwrResponse = $_.Exception.Response
        $messageText = $_.Exception.Message
        $statusCode = $iwrResponse.StatusCode.Value__
        $headers = $iwrResponse.Headers
        Get-GitHubRateLimit $headers
        if ($statusCode -eq 403 -or $messageText -match "rate limit") {
            Write-Warning "Rate limited. Waiting 60 seconds before retry..."
            Start-Sleep -Seconds 60
            return Get-ReleaseTag
        } elseif ($statusCode -ge 500 -or $messageText -match "timeout") {
            Write-Warning "Timed out. Waiting 60 seconds before retry..."
            Start-Sleep -Seconds 60
            return Get-ReleaseTag
        }
        throw $_.Exception
    }
    $releasesAPIResponse = $releasesAPIResponse.Where({ !$_.prerelease })
    if ($releasesAPIResponse.Count -lt 1) {
        Write-Output "No WinGet releases found matching criteria"
        exit 1
    }
    $releasesAPIResponse = $releasesAPIResponse | Sort-Object -Property published_at -Descending
    return $releasesAPIResponse[0].tag_name
}

while ($true) {
    try {
        Get-GitHubRateLimit
        Write-Host "=== Repositories ==="
        Get-PSRepository | Format-List * | Out-String | Write-Host
        Write-Host "=== Package Sources ==="
        Get-PackageSource | Format-List * | Out-String | Write-Host
        Write-Host "=== Package Providers ==="
        Get-PackageProvider | Format-List * | Out-String | Write-Host
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false
        }
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Verbose -AllowClobber
        Repair-WinGetPackageManager -Version $(Get-ReleaseTag -Verbose) -Force -Verbose -AllUsers
        Get-GitHubRateLimit
        break
    } catch {
        $messageText = $_.Exception.Message
        Write-Warning "Repair failed: $($messageText)"
        if ($messageText -match "0x80073D02") {
            if ($messageText -match "ActivityId\]\s+([0-9a-fA-F-]+)") {
                $activityId = $matches[1]
                Write-Output "Found ActivityId: $activityId"
                try {
                    Write-Output "Retrieving AppX logs..."
                    Get-AppPackageLog -ActivityId $activityId | Format-List
                } catch {
                    Write-Warning "Could not retrieve AppX log for $activityId"
                }
            }
        } elseif ($messageText -match "rate limit|429|timeout|timed out|failed to respond|connection attempt failed") {
            Write-Warning "Transient network error. Waiting 60 seconds before retry..."
            Start-Sleep -Seconds 60
            continue
        } elseif ($messageText -match "unable to find repository") {
            Write-Warning "Try to re-register before retrying..."
            try {
                Get-PSRepository
                Import-Module PackageManagement -Force
                Import-Module PowerShellGet -Force
                Register-PSRepository -Default
                if ($(Get-PSRepository).Name -in "PSGallery") {
                    continue
                }
            } catch {
                Write-Warning "Register-PSRepository failed: $($_.Exception.Message)"
            }
        }
        Write-Error -ErrorRecord $_ -ErrorAction Continue
        throw $_
    }
}
