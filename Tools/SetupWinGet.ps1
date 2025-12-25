function Get-ReleaseTag {
	[CmdletBinding()]
	param()
	try {
		$iwrParams = @{Uri = "https://api.github.com/repos/microsoft/winget-cli/releases?per_page=100"}
		if ($PSBoundParameters.ContainsKey("Verbose")) {
			$iwrParams["Verbose"] = $true
		}
		$response  = Invoke-WebRequest @iwrParams
		$releasesAPIResponse = $response.Content | ConvertFrom-Json
		$limit     = $response.Headers["X-RateLimit-Limit"]
		$remaining = $response.Headers["X-RateLimit-Remaining"]
		$reset     = $response.Headers["X-RateLimit-Reset"]
		if ($limit     -is [array]) { $limit     = $limit[0] }
		if ($remaining -is [array]) { $remaining = $remaining[0] }
		if ($reset     -is [array]) { $reset     = $reset[0] }
		$limit     = [int]$limit
		$remaining = [int]$remaining
		$resetTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$reset)
		$currTime  = [DateTimeOffset]::Now.LocalDateTime
		Write-Warning "GitHub API rate limit: $remaining / $limit remaining - resets at $($resetTime.LocalDateTime) (now $($currTime))"
	} catch {
		$statusCode = $_.Exception.Response.StatusCode.Value__
		$messageText = $_.Exception.Message
		if ($statusCode -eq 403 -or $messageText -match "rate limit") {
			Write-Warning "Rate limited. Waiting 60 seconds before retry..."
			Start-Sleep -Seconds 60
			return Get-ReleaseTag
		} elseif ($statusCode -ge 500 -or $messageText -match "timeout") {
			Write-Warning "Rate limited. Waiting 60 seconds before retry..."
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
		Install-PackageProvider -Name NuGet -Force -Verbose
		Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Verbose -AllowClobber
		Repair-WinGetPackageManager -Version $(Get-ReleaseTag -Verbose) -Force -Verbose
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
		} elseif ($messageText -match "rate limit") {
			Write-Warning "Rate limited. Waiting 60 seconds before retry..."
			Start-Sleep -Seconds 60
			continue
		} elseif ($messageText -match "timeout") {
			Write-Warning "Timed out. Waiting 60 seconds before retry..."
			Start-Sleep -Seconds 60
			continue
		}
		throw $_.Exception
	}
}
