param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

foreach ($pathStr in $Paths) {
    try {
        $path = Get-Item -LiteralPath $pathStr -ErrorAction Stop
    } catch {
        Write-Host "Path doesn't exist: $pathStr" -ForegroundColor Yellow
        continue
    }

    if (-not $path.PSIsContainer -and @(".yml", ".yaml") -contains $path.Extension.ToLower()) {
        $filePaths = @($path)
    } elseif ($path.PSIsContainer) {
        $filePaths = Get-ChildItem -LiteralPath $path.FullName -Recurse -File |
            Where-Object {
                $_.Extension.ToLower() -in @(".yml", ".yaml")
            } | Sort-Object FullName -Unique
    } else {
        continue
    }

    $folderPaths = $filePaths | Select-Object -ExpandProperty DirectoryName -Unique
    foreach ($folder in $folderPaths) {
        Write-Host "Folder: $folder"
        winget validate $folder
    }
}
