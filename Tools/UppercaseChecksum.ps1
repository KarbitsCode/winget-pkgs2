param(
    [string]$Target,
    [string]$Type = 'sha256'
)

function Get-RemoteChecksum {
	param(
		[string]$Url,
		[string]$Algorithm = 'sha256'
	)

	$fn = New-TemporaryFile
	try {
		if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
			& curl.exe -L $Url -o $fn
			if ($LASTEXITCODE -ne 0) {
				throw "curl.exe failed with exit code $LASTEXITCODE"
			}
		}
	} catch {
		Write-Warning "curl.exe failed: $_"
		Write-Warning "Falling back to Invoke-WebRequest..."
		Invoke-WebRequest $Url -OutFile $fn -UseBasicParsing
	}
	$res = Get-FileHash $fn -Algorithm $Algorithm | ForEach-Object Hash
	Remove-Item $fn -Force -ErrorAction Ignore
	return $res.ToLower()
}

Write-Host $(Get-RemoteChecksum -Url $Target -Algorithm $Type).ToUpper() -ForegroundColor Yellow
