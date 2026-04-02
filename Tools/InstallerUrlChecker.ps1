param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url
)

$fn = New-TemporaryFile

$rs = Invoke-WebRequest $Url -OutFile $fn -UseBasicParsing -PassThru
$rs.Headers.Keys | ForEach-Object {
    "$($_): $($rs.Headers[$_])"
}
"`n"
$fl = Get-Item $fn
$fl.VersionInfo.PSObject.Properties | ForEach-Object {
	"$($_.Name): $($_.Value)"
}

Remove-Item $fn -Force -ErrorAction Ignore
