param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

Push-Location .\winget-pkgs\

$parts = $Path -split '[\\/]'
if ($parts.Count -lt 5 -or $parts[0] -ne 'manifests') {
    throw "Invalid path: $Path"
}
$version = $parts[-1]
$id = ($parts[2..($parts.Count - 2)] -join '.')
$prTitle = "$id version $version"

gh pr list `
    --search "$prTitle in:title" `
    --author "@me" `
    --state open `
    --json number,title,url

Pop-Location
