Param(
  [Parameter(Position = 0, HelpMessage = 'The Manifest to install in the Sandbox.')]
  [String] $Manifest,
  [Parameter(HelpMessage = 'Disable spinner animation when installing package (for CI)')]
  [switch] $DisableSpinner,
  [Parameter(HelpMessage = 'Additional options for WinGet')]
  [string] $WinGetOptions
)

function Update-EnvironmentVariables {
  foreach($level in "Machine","User") {
    [Environment]::GetEnvironmentVariables($level).GetEnumerator() | % {
        # For Path variables, append the new values, if they're not already in there
        if($_.Name -match '^Path$') {
          $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select -unique) -join ';'
        }
        $_
    } | Set-Content -Path { "Env:$($_.Name)" }
  }
}

function Get-ARPTable {
  $registry_paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
  return Get-ItemProperty $registry_paths -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and (-not $_.SystemComponent -or $_.SystemComponent -ne 1 ) } |
      Select-Object DisplayName, DisplayVersion, Publisher, @{N='ProductCode'; E={$_.PSChildName}}, @{N='Scope'; E={if($_.PSDrive.Name -eq 'HKCU') {'User'} else {'Machine'}}}
}

Write-Host @'
--> Installing WinGet
'@

Write-Host @'
--> Disabling safety warning when running installer
'@
# New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' | Out-Null
# New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' -Name 'ModRiskFileTypes' -Type 'String' -Value '.bat;.exe;.reg;.vbs;.chm;.msi;.js;.cmd' | Out-Null

Write-Host @'
Tip: you can type 'Update-EnvironmentVariables' to update your environment variables, such as after installing a new software.
'@

Write-Host @'

--> Configuring Winget
'@
winget settings --Enable LocalManifestFiles
winget settings --Enable LocalArchiveMalwareScanOverride

$p = (winget settings export | ConvertFrom-Json).userSettingsFile

if ($DisableSpinner) {
  if (Test-Path $p) {
    Copy-Item $p "$p.bak" -Force
    $raw = Get-Content $p -Raw
    # Remove line comments
    $raw = $raw -replace '(?m)^\s*//.*$' -replace ',(\s*[}\]])', '$1'
    $j = $raw | ConvertFrom-Json
    if (-not $j.visual) { $j.visual = @{} }
    $j.visual.progressBar = 'disabled'
    $j | ConvertTo-Json -Depth 10 | Set-Content $p -Encoding UTF8
  }
}

$originalARP = Get-ARPTable
$geoID = (Get-WinHomeLocation).GeoID
Set-WinHomeLocation -GeoID $geoID
$manifestFileName = Split-Path $Manifest -Leaf
Write-Host @"

--> Validating the Manifest $manifestFileName

"@
winget validate --manifest $Manifest --verbose-logs

Write-Host @"

--> Installing the Manifest $manifestFileName

"@
winget install --manifest $Manifest --verbose-logs --ignore-local-archive-malware-scan --dependency-source winget @($WinGetOptions -split ' ')

Write-Host @'

--> Refreshing environment variables
'@
Update-EnvironmentVariables

Write-Host @'

--> Comparing ARP Entries
'@
$diff = (Compare-Object (Get-ARPTable) $originalARP -Property DisplayName,DisplayVersion,Publisher,ProductCode,Scope)| Select-Object -Property * -ExcludeProperty SideIndicator
$diff | Format-Table -Wrap
$diff | ConvertTo-Json -Compress | Set-Content -Path "$([System.IO.Path]::GetTempPath())\arp.json" -Encoding UTF8

# Restore the settings
if (Test-Path $p) {
  if (Test-Path "$p.bak") {
    Move-Item "$p.bak" $p -Force
  }
}

