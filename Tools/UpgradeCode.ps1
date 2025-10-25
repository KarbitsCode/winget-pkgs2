$wmipackages = Get-CimInstance -ClassName win32_product
$wmiproperties = Get-CimInstance -Query "SELECT ProductCode,Value FROM Win32_Property WHERE Property='UpgradeCode'"
$packageinfo = New-Object System.Data.Datatable
[void]$packageinfo.Columns.Add("Name")
[void]$packageinfo.Columns.Add("ProductCode")
[void]$packageinfo.Columns.Add("UpgradeCode")

foreach ($package in $wmipackages) {
    $foundupgradecode = $false # Assume no upgrade code is found

    foreach ($property in $wmiproperties) {
        if ($package.IdentifyingNumber -eq $property.ProductCode) {
            [void]$packageinfo.Rows.Add($package.Name,$package.IdentifyingNumber, $property.Value)
            $foundupgradecode = $true
            break
        }
    }

    if(-not ($foundupgradecode)) {
        # No upgrade code found, add product code to list
        [void]$packageinfo.Rows.Add($package.Name,$package.IdentifyingNumber, "")
    }
}

$packageinfo | Sort-Object -Property Name | Format-Table ProductCode, UpgradeCode, Name -Wrap

