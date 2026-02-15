Param(
  [Parameter(Position = 0, HelpMessage = 'The Manifest to install in the Sandbox.')]
  [String] $Manifest,
  [Parameter(HelpMessage = 'Disable spinner animation when installing a package')]
  [switch] $DisableSpinner,
  [Parameter(HelpMessage = 'Strip progress bar when installing a package')]
  [switch] $StripProgress,
  [Parameter(HelpMessage = 'Automatically uninstall newly installed package')]
  [switch] $AutoUninstall,
  [Parameter(HelpMessage = 'Additional options for WinGet')]
  [string] $WinGetOptions
)

function Update-EnvironmentVariables {
  foreach($level in "Machine","User") {
    [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
        # For Path variables, append the new values, if they're not already in there
        if($_.Name -match '^Path$') {
          $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select-Object -unique) -join ';'
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

# https://gist.github.com/asheroto/96bcabe428e8ad134ef204573810041f
function Strip-Progress {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ScriptBlock]$ScriptBlock
  )

  # Regex pattern to match spinner characters and progress bar patterns
  $progressPattern = 'Γû[Æê]|^\s+[-\\|/]\s+$'

  # Corrected regex pattern for size formatting, ensuring proper capture groups are utilized
  $sizePattern = '(\d+(\.\d{1,2})?)\s+(B|KB|MB|GB|TB|PB) /\s+(\d+(\.\d{1,2})?)\s+(B|KB|MB|GB|TB|PB)'

  $previousLineWasEmpty = $false # Track if the previous line was empty

  & $ScriptBlock 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
      "ERROR: $($_.Exception.Message)"
    } elseif ($_ -match '^\s*$') {
      if (-not $previousLineWasEmpty) {
        Write-Output ""
        $previousLineWasEmpty = $true
      }
    } else {
      $line = $_ -replace $progressPattern, '' -replace $sizePattern, '$1 $3 / $4 $6'
      if (-not [string]::IsNullOrWhiteSpace($line)) {
        $previousLineWasEmpty = $false
        $line
      }
    }
  }
}

function Add-NestedJsonValue {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    $Object,
    [Parameter(Mandatory = $true, Position = 1)]
    [string[]]$Path,
    [Parameter(Mandatory = $true, Position = 2)]
    $Value
  )

  $current = $Object
  for ($i = 0; $i -lt $Path.Count; $i++) {
    $key = $Path[$i]
    $isLast = ($i -eq $Path.Count - 1)
    if ($isLast) {
      if (-not $current.PSObject.Properties[$key]) {
        $current | Add-Member -NotePropertyName $key -NotePropertyValue $Value
      } else {
        $current.$key = $Value
      }
    } else {
      if (-not $current.PSObject.Properties[$key]) {
        $current | Add-Member -NotePropertyName $key -NotePropertyValue ([PSCustomObject]@{})
      }
      $current = $current.$key
    }
  }
}


Write-Host @'
--> Installing WinGet
'@

Write-Host @'
--> Disabling safety warning when running installer
'@
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' -Force | Out-Null
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' -Name 'ModRiskFileTypes' -Type 'String' -Value '.bat;.exe;.reg;.vbs;.chm;.msi;.js;.cmd' -Force | Out-Null

Write-Host @'
Tip: you can type 'Update-EnvironmentVariables' to update your environment variables, such as after installing a new software.
'@

Write-Host @'

--> Configuring WinGet
'@
winget settings --Enable LocalManifestFiles
winget settings --Enable LocalArchiveMalwareScanOverride

$p = (winget settings export | ConvertFrom-Json).userSettingsFile

if (Test-Path $p) {
  if (Test-Path "$p.bak") {
    Move-Item "$p.bak" $p -Force
  }
  Copy-Item $p "$p.bak" -Force
  $raw = Get-Content $p -Raw
  $raw = $raw -replace '(?m)^\s*//.*$' -replace ',(\s*[}\]])', '$1' # Remove line comments
  $j = $raw | ConvertFrom-Json
  Add-NestedJsonValue -Object $j -Path @('uninstallBehavior', 'purgePortablePackage') -Value $true
  if ($DisableSpinner) {
    Add-NestedJsonValue -Object $j -Path @('visual', 'progressBar') -Value 'disabled'
  }
  $j | ConvertTo-Json | Set-Content $p -Encoding UTF8
}

Remove-Item "$env:TEMP\WinGet" -Recurse -Force -ErrorAction SilentlyContinue

$originalARP = Get-ARPTable
$geoID = (Get-WinHomeLocation).GeoID
Set-WinHomeLocation -GeoID $geoID
$manifestFileName = "$((Get-ChildItem -Path $Manifest -Filter '*.yaml' | Select-Object -First 1).BaseName -replace '\.(installer|locale\.[\w-]+)$','') $(Split-Path $Manifest -Leaf)"
Write-Host @"

--> Validating the manifest $manifestFileName

"@
winget validate --manifest $Manifest --verbose-logs

Write-Host @"

--> Installing the manifest $manifestFileName

"@
$scriptBlock = { winget install --manifest $Manifest --verbose-logs --ignore-local-archive-malware-scan --accept-package-agreements --accept-source-agreements --disable-interactivity --dependency-source winget @($WinGetOptions -split ' ') }
if ($StripProgress) {
  Strip-Progress -ScriptBlock $scriptBlock
} else {
  & $scriptBlock
}
$installResult = @{ ExitCode = $LASTEXITCODE }

Write-Host @'

--> Refreshing environment variables
'@
Update-EnvironmentVariables

Write-Host @'

--> Comparing ARP Entries
'@
$diff = (Compare-Object (Get-ARPTable) $originalARP -Property DisplayName,DisplayVersion,Publisher,ProductCode,Scope)| Select-Object -Property * -ExcludeProperty SideIndicator
$diff | Format-Table -Wrap

if ($AutoUninstall) {
  if ($diff) {
Write-Host @"

--> Uninstalling the manifest $manifestFileName

"@
  }
  $uninstallResult = @()
  foreach ($item in $diff) {
    $code = $item.ProductCode
    if ($code) {
      $scriptBlock = { winget uninstall --product-code $code --verbose-logs --accept-source-agreements --disable-interactivity }
      if ($StripProgress) {
        Strip-Progress -ScriptBlock $scriptBlock
      } else {
        & $scriptBlock
      }
      $uninstallResult += [PSCustomObject]@{
        ProductCode = $code
        ExitCode = $LASTEXITCODE
      }
    }
  }
}

[PSCustomObject]@{
  InstallResult = $installResult
  ARPDiff = $diff
  UninstallResult = $uninstallResult
} | ConvertTo-Json | Set-Content -Path "$([System.IO.Path]::GetTempPath())\arp.json" -Encoding UTF8

# Restore the settings
if (Test-Path $p) {
  if (Test-Path "$p.bak") {
    Move-Item "$p.bak" $p -Force
  }
}

