param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Urls
)

foreach ($Url in $Urls) {
    Write-Host "Checking $($Url)..." -ForegroundColor Yellow
    $fn = New-TemporaryFile
    $rs = Invoke-WebRequest $Url -OutFile $fn -UseBasicParsing -PassThru
    $rs.Headers.Keys | ForEach-Object {
        Write-Host "$($_): $($rs.Headers[$_])"
    }
    Write-Host ""
    $fl = Get-Item $fn
    $bytes = [System.IO.File]::ReadAllBytes($fl.FullName)[0..1]
    $isExe = ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A)   # "MZ"

    if ($isExe) {
        $fl.VersionInfo.PSObject.Properties | ForEach-Object {
            Write-Host "$($_.Name): $($_.Value)"
        }
        Write-Host ""
        $sig = Get-AuthenticodeSignature -FilePath $fl.FullName
        Write-Host "Signature status: $($sig.Status)"
        if ($sig.StatusMessage) {
            Write-Host "Signature message: $($sig.StatusMessage)"
        }
        if ($sig.SignerCertificate) {
            Write-Host "Signer Certificate:"
            Write-Host ($sig.SignerCertificate |
                Select-Object * -ExcludeProperty RawData, Handle |
                Format-List | Out-String).Trim()
        }
        if ($sig.TimeStamperCertificate) {
            Write-Host "TimeStamper Certificate:"
            Write-Host ($sig.TimeStamperCertificate |
                Select-Object * -ExcludeProperty RawData, Handle |
                Format-List | Out-String).Trim()
        }
    } else {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($fl.FullName)
            $zip.Entries | ForEach-Object {
                Write-Host "File: $($_.FullName) ($($_.CompressedLength) / $($_.Length) ($([math]::Round(($_.CompressedLength / [math]::Max($_.Length, 1))*100, 2))%))"
            }
            $zip.Dispose()
        } catch {
            Write-Host "Not a zip and not an exe."
        }
    }
    Write-Host ""
    Write-Host "SHA256: $($(Get-FileHash -Path $fn -Algorithm 'sha256' | ForEach-Object Hash).ToUpper())"
    Write-Host ""
    Remove-Item $fn -Force -ErrorAction Ignore
}
