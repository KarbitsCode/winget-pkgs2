param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url
)

$fn = New-TemporaryFile

$rs = Invoke-WebRequest $Url -OutFile $fn -UseBasicParsing -PassThru
$rs.Headers.Keys | ForEach-Object {
    Write-Host "$($_): $($rs.Headers[$_])"
}
Write-Host ""
$fl = Get-Item $fn
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($fl.FullName)
    $zip.Entries | ForEach-Object {
        Write-Host "File: $($_.FullName) ($($_.CompressedLength) / $($_.Length) ($([math]::Round(($_.CompressedLength / [math]::Max($_.Length, 1))*100, 2))%))"
    }
    $zip.Dispose()
} catch {
    $fl.VersionInfo.PSObject.Properties | ForEach-Object {
        Write-Host "$($_.Name): $($_.Value)"
    }
}
Write-Host ""
Write-Host "SHA256: $($(Get-FileHash -Path $fn -Algorithm 'sha256' | ForEach-Object Hash).ToUpper())"

Remove-Item $fn -Force -ErrorAction Ignore
