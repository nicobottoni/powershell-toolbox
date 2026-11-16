<#
.SYNOPSIS
    Export Microsoft Universal Print printer locations to a semicolon-delimited CSV.

.DESCRIPTION
    Lists Universal Print shares, optionally filters them by a ShareName prefix
    (for example PN3126), retrieves the associated printer and exports its
    location properties. The printer hostname is not used for matching.

.REQUIREMENTS
    Windows PowerShell 5.1 or later
    Microsoft.Graph.Authentication module
    Delegated permissions: PrinterShare.Read.All, Printer.Read.All
#>

# ============================================================
# Check Microsoft Graph module
# ============================================================

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host "Microsoft.Graph.Authentication is not installed." -ForegroundColor Yellow
    Write-Host "Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    exit
}

try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}
catch {
    Write-Host "Failed to import Microsoft.Graph.Authentication." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

# ============================================================
# Load Windows Forms
# ============================================================

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
}
catch {
    Write-Host "Failed to load System.Windows.Forms." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

function Disconnect-GraphSafely {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # No action required.
    }
}

function Get-GraphCollection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $Items = @()
    $NextUri = $Uri

    while ($NextUri) {
        $Response = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $NextUri `
            -ErrorAction Stop

        $Items += @($Response.value)
        $NextUri = $Response.'@odata.nextLink'
    }

    return $Items
}

function ConvertTo-CsvLocationValue {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [System.Array]) {
        return (($Value | ForEach-Object { [string]$_ }) -join "|")
    }

    return [string]$Value
}

# ============================================================
# Select ShareName filter
# ============================================================

Write-Host ""
Write-Host "ShareName filter (e.g. PN3126). Leave empty to export all shares." -ForegroundColor Cyan
$ShareNamePrefix = (Read-Host "ShareName starts with").Trim()

if ([string]::IsNullOrWhiteSpace($ShareNamePrefix)) {
    $ShareNamePrefix = ""
    Write-Host "No filter selected; all Universal Print shares will be exported." -ForegroundColor Yellow
}
else {
    Write-Host "Only ShareNames beginning with '$ShareNamePrefix' will be exported." -ForegroundColor Cyan
}

# ============================================================
# Connect and retrieve shares and associated printer locations
# ============================================================

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

try {
    Connect-MgGraph `
        -Scopes @("PrinterShare.Read.All", "Printer.Read.All") `
        -NoWelcome `
        -ErrorAction Stop
}
catch {
    Write-Host "Failed to connect to Microsoft Graph." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

$ExportRows = @()

try {
    Write-Host "Retrieving Universal Print shares..." -ForegroundColor Cyan
    $Shares = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/print/shares")

    if (-not [string]::IsNullOrWhiteSpace($ShareNamePrefix)) {
        $Shares = @(
            $Shares | Where-Object {
                $_.displayName -and
                $_.displayName.StartsWith($ShareNamePrefix, [System.StringComparison]::OrdinalIgnoreCase)
            }
        )
    }

    if ($Shares.Count -eq 0) {
        Write-Host "No printer shares matched the selected filter." -ForegroundColor Yellow
    }
    else {
        Write-Host "$($Shares.Count) share(s) matched. Retrieving printer location details..." -ForegroundColor Cyan
    }

    $Counter = 0
    foreach ($Share in $Shares) {
        $Counter++
        $ShareName = [string]$Share.displayName
        Write-Host "[$Counter/$($Shares.Count)] $ShareName" -ForegroundColor Cyan

        try {
            # The printer is a navigation property of a printer share.
            # Resolve it via Graph so the export uses ShareName, not hostname.
            $EncodedShareId = [uri]::EscapeDataString([string]$Share.id)
            $Printer = Invoke-MgGraphRequest `
                -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/print/shares/$EncodedShareId/printer" `
                -ErrorAction Stop

            $Location = $Printer.location

            $ExportRows += [PSCustomObject]@{
                ShareName          = $ShareName
                ShareId            = [string]$Share.id
                PrinterDisplayName = [string]$Printer.displayName
                PrinterId          = [string]$Printer.id
                Latitude           = ConvertTo-CsvLocationValue $Location.latitude
                Longitude          = ConvertTo-CsvLocationValue $Location.longitude
                AltitudeInMeters   = ConvertTo-CsvLocationValue $Location.altitudeInMeters
                Organization       = ConvertTo-CsvLocationValue $Location.organization
                Subdivision        = ConvertTo-CsvLocationValue $Location.subdivision
                Site               = ConvertTo-CsvLocationValue $Location.site
                SubUnit            = ConvertTo-CsvLocationValue $Location.subUnit
                Building           = ConvertTo-CsvLocationValue $Location.building
                Floor              = ConvertTo-CsvLocationValue $Location.floor
                FloorDescription   = ConvertTo-CsvLocationValue $Location.floorDescription
                RoomName           = ConvertTo-CsvLocationValue $Location.roomName
                RoomDescription    = ConvertTo-CsvLocationValue $Location.roomDescription
                StreetAddress      = ConvertTo-CsvLocationValue $Location.streetAddress
                City               = ConvertTo-CsvLocationValue $Location.city
                StateOrProvince    = ConvertTo-CsvLocationValue $Location.stateOrProvince
                PostalCode         = ConvertTo-CsvLocationValue $Location.postalCode
                CountryOrRegion    = ConvertTo-CsvLocationValue $Location.countryOrRegion
                Error              = ""
            }
        }
        catch {
            Write-Host "Could not retrieve printer/location for share '$ShareName'." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red

            $ExportRows += [PSCustomObject]@{
                ShareName          = $ShareName
                ShareId            = [string]$Share.id
                PrinterDisplayName = ""
                PrinterId          = ""
                Latitude           = ""
                Longitude          = ""
                AltitudeInMeters   = ""
                Organization       = ""
                Subdivision        = ""
                Site               = ""
                SubUnit            = ""
                Building           = ""
                Floor              = ""
                FloorDescription   = ""
                RoomName           = ""
                RoomDescription    = ""
                StreetAddress      = ""
                City               = ""
                StateOrProvince    = ""
                PostalCode         = ""
                CountryOrRegion    = ""
                Error              = $_.Exception.Message
            }
        }
    }
}
catch {
    Write-Host "Failed to retrieve Universal Print shares." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Disconnect-GraphSafely
    exit
}

# ============================================================
# Export CSV
# ============================================================

if ($ExportRows.Count -gt 0) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    if ([string]::IsNullOrWhiteSpace($ShareNamePrefix)) {
        $DefaultFileName = "UniversalPrint_Locations_All_$Timestamp.csv"
    }
    else {
        $SafePrefix = $ShareNamePrefix -replace '[\\/:*?"<>|]', '_'
        $DefaultFileName = "UniversalPrint_Locations_$SafePrefix`_$Timestamp.csv"
    }

    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveDialog.Title = "Save Universal Print Locations"
    $SaveDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $SaveDialog.FileName = $DefaultFileName
    $SaveDialog.DefaultExt = "csv"
    $SaveDialog.AddExtension = $true
    $SaveDialog.OverwritePrompt = $true
    $SaveDialog.CheckPathExists = $true
    $SaveDialog.RestoreDirectory = $true

    if ($SaveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $ExportRows |
                Sort-Object ShareName |
                Export-Csv `
                    -Path $SaveDialog.FileName `
                    -Delimiter ";" `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -ErrorAction Stop

            Write-Host ""
            Write-Host "Export completed: $($ExportRows.Count) row(s)." -ForegroundColor Green
            Write-Host $SaveDialog.FileName -ForegroundColor Cyan
        }
        catch {
            Write-Host "Failed to export the CSV file." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    else {
        Write-Host "Export cancelled. No CSV file was created." -ForegroundColor Yellow
    }
}
else {
    Write-Host "No data to export." -ForegroundColor Yellow
}

# ============================================================
# Disconnect Microsoft Graph
# ============================================================

Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
Disconnect-GraphSafely
Write-Host "Done." -ForegroundColor Green
