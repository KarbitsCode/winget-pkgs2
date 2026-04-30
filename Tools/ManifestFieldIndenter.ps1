param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FolderOrFile
)

if (Test-Path $FolderOrFile -PathType Leaf) {
    $FolderOrFile = Split-Path $FolderOrFile -Parent
}

$fields = @(
  "InstallerType",
  "Scope",
  "InstallModes",
  "UpgradeBehavior",
  "ProductCode",
  "AppsAndFeaturesEntries",
  "ElevationRequirement",
  "InstallationMetadata",
  "Protocols",
  "FileExtensions"
)

Get-ChildItem -Path $FolderOrFile -Recurse -File -Filter "*.installer.yaml" | ForEach-Object {
    $file = $_.FullName
    Write-Host "Processing $file"
    $raw = Get-Content $file -Raw
    $yaml = $raw | ConvertFrom-Yaml
    $headers = @()
    foreach ($line in $raw -split "`r?`n") {
        if ($line -match '^\s*#' -or $line -match '^\s*$') {
            $headers += $line
        } else {
            break
        }
    }
    
    if (-not $yaml.ContainsKey("InstallerType")) {
        Write-Warning "Missing top-level fields: InstallerType"
        return
    }
    
    $newInstallers = @()
    
     foreach ($installer in $yaml.Installers) {
         $map = [ordered]@{}
         
         foreach ($k in $installer.Keys) {
             $map[$k] = $installer[$k]
         }
         
         foreach ($field in $fields) {
             if ($yaml.ContainsKey($field)) {
                 $map[$field] = $yaml[$field]
             }
         }
         
         $newInstallers += [PSCustomObject]$map
     }
    
    $resultMap = [ordered]@{}
    
    $resultMap["PackageIdentifier"] = $yaml.PackageIdentifier
    $resultMap["PackageVersion"]    = $yaml.PackageVersion
    $resultMap["InstallerLocale"]   = $yaml.InstallerLocale
    
    if ($yaml.ContainsKey("Dependencies")) {
        $resultMap["Dependencies"]  = $yaml.Dependencies
    }
    
    $resultMap["Installers"]        = $newInstallers
    $resultMap["ManifestType"]      = $yaml.ManifestType
    $resultMap["ManifestVersion"]   = $yaml.ManifestVersion
    $resultMap["ReleaseDate"]       = $yaml.ReleaseDate
    
    $body = $resultMap | ConvertTo-Yaml
    
    $fin = @(
        $headers
        $body
    ) -join "`r`n"
    
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($file, $fin, $utf8)
}
