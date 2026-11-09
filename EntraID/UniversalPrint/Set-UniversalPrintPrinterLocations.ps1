<#
.SYNOPSIS
    Bulk update Microsoft Universal Print printer locations from CSV.

.DESCRIPTION
    Imports printer location data from a semicolon-delimited CSV file.
    Matches printers by their Universal Print display name.
    Validates all entries before making changes.
    Updates printer location properties through Microsoft Graph.
    Optionally exports a result log to a user-selected location.

.REQUIREMENTS
    Windows PowerShell 5.1 or later
    Microsoft.Graph.Authentication module
    Delegated permission: Printer.ReadWrite.All
#>


# ============================================================
# Functions
# ============================================================

function Add-StringProperty {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Target[$Name] = $Value.Trim()
    }
}


function Add-CollectionProperty {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {

        # Multiple hierarchy values can be separated with |
        # Example:
        # Europe|Switzerland|IT

        $Values = @(
            $Value.Split("|") |
            ForEach-Object {
                $_.Trim()
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
        )

        if ($Values.Count -gt 0) {
            $Target[$Name] = $Values
        }
    }
}


function Add-DoubleProperty {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {

        $NormalizedValue = $Value.Trim().Replace(",", ".")
        [double]$ParsedValue = 0

        $Success = [double]::TryParse(
            $NormalizedValue,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$ParsedValue
        )

        if (-not $Success) {
            throw "Invalid numeric value '$Value' for property '$Name'."
        }

        $Target[$Name] = $ParsedValue
    }
}


function Add-IntegerProperty {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {

        [int]$ParsedValue = 0

        $Success = [int]::TryParse(
            $Value.Trim(),
            [ref]$ParsedValue
        )

        if (-not $Success) {
            throw "Invalid integer value '$Value' for property '$Name'."
        }

        $Target[$Name] = $ParsedValue
    }
}


function Test-NumericString {
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    return $Value.Trim() -match '^\d+$'
}


function Disconnect-GraphSafely {

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # No action required
    }
}


# ============================================================
# Check Microsoft Graph module
# ============================================================

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {

    Write-Host ""
    Write-Host "Microsoft.Graph.Authentication is not installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install it with:"
    Write-Host "Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    Write-Host ""

    exit
}

try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}
catch {

    Write-Host ""
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

    Write-Host ""
    Write-Host "Failed to load System.Windows.Forms." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit
}


# ============================================================
# Select CSV file
# ============================================================

$FileDialog = New-Object System.Windows.Forms.OpenFileDialog

$FileDialog.Title = "Select Universal Print Location CSV"
$FileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
$FileDialog.Multiselect = $false
$FileDialog.CheckFileExists = $true
$FileDialog.CheckPathExists = $true
$FileDialog.RestoreDirectory = $true

$DialogResult = $FileDialog.ShowDialog()

if ($DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {

    Write-Host ""
    Write-Host "No CSV file selected. Operation cancelled." -ForegroundColor Yellow

    exit
}

$CsvPath = $FileDialog.FileName

Write-Host ""
Write-Host "Selected CSV:" -ForegroundColor Cyan
Write-Host $CsvPath


# ============================================================
# Import CSV
# ============================================================

try {

    $CsvData = @(
        Import-Csv `
            -Path $CsvPath `
            -Delimiter ";" `
            -Encoding UTF8 `
            -ErrorAction Stop
    )
}
catch {

    Write-Host ""
    Write-Host "Failed to import the CSV file." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit
}

if ($CsvData.Count -eq 0) {

    Write-Host ""
    Write-Host "The CSV file contains no printer entries." -ForegroundColor Yellow

    exit
}


# ============================================================
# Validate CSV structure
# ============================================================

$RequiredColumns = @(
    "PrinterName",
    "Latitude",
    "Longitude",
    "AltitudeInMeters",
    "Organization",
    "Subdivision",
    "Site",
    "SubUnit",
    "Building",
    "Floor",
    "FloorDescription",
    "RoomName",
    "RoomDescription",
    "StreetAddress",
    "City",
    "StateOrProvince",
    "PostalCode",
    "CountryOrRegion"
)

$AvailableColumns = @(
    $CsvData[0].PSObject.Properties.Name
)

$MissingColumns = @(
    $RequiredColumns |
    Where-Object {
        $_ -notin $AvailableColumns
    }
)

if ($MissingColumns.Count -gt 0) {

    Write-Host ""
    Write-Host "The CSV file is missing required columns:" -ForegroundColor Red
    Write-Host ""

    foreach ($Column in $MissingColumns) {
        Write-Host " - $Column" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Please correct the CSV file before continuing." -ForegroundColor Red

    exit
}


# ============================================================
# Validate PrinterName values
# ============================================================

$InvalidRows = @(
    $CsvData |
    Where-Object {
        [string]::IsNullOrWhiteSpace($_.PrinterName)
    }
)

if ($InvalidRows.Count -gt 0) {

    Write-Host ""
    Write-Host "$($InvalidRows.Count) CSV row(s) have no PrinterName." -ForegroundColor Red
    Write-Host "Please correct the CSV file before continuing." -ForegroundColor Red

    exit
}


# ============================================================
# Trim PrinterName values
# ============================================================

foreach ($Row in $CsvData) {
    $Row.PrinterName = $Row.PrinterName.Trim()
}


# ============================================================
# Check duplicate printer names
# ============================================================

$DuplicatePrinterNames = @(
    $CsvData |
    Group-Object PrinterName |
    Where-Object {
        $_.Count -gt 1
    }
)

if ($DuplicatePrinterNames.Count -gt 0) {

    Write-Host ""
    Write-Host "Duplicate printer names found in the CSV:" -ForegroundColor Red
    Write-Host ""

    foreach ($Duplicate in $DuplicatePrinterNames) {
        Write-Host " - $($Duplicate.Name)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Please remove duplicate entries before continuing." -ForegroundColor Red

    exit
}


# ============================================================
# Validate Floor and RoomName
# ============================================================

$InvalidFloorRows = @(
    $CsvData |
    Where-Object {
        -not (Test-NumericString -Value $_.Floor)
    }
)

$InvalidRoomRows = @(
    $CsvData |
    Where-Object {
        -not (Test-NumericString -Value $_.RoomName)
    }
)

if ($InvalidFloorRows.Count -gt 0) {

    Write-Host ""
    Write-Host "The following printers contain a non-numeric Floor value:" -ForegroundColor Red
    Write-Host ""

    foreach ($Row in $InvalidFloorRows) {
        Write-Host " - $($Row.PrinterName): $($Row.Floor)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Floor must be empty or contain numbers only." -ForegroundColor Red

    exit
}

if ($InvalidRoomRows.Count -gt 0) {

    Write-Host ""
    Write-Host "The following printers contain a non-numeric RoomName value:" -ForegroundColor Red
    Write-Host ""

    foreach ($Row in $InvalidRoomRows) {
        Write-Host " - $($Row.PrinterName): $($Row.RoomName)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "RoomName must be empty or contain numbers only." -ForegroundColor Red

    exit
}


# ============================================================
# Connect to Microsoft Graph
# ============================================================

Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

try {

    Connect-MgGraph `
        -Scopes "Printer.ReadWrite.All" `
        -NoWelcome `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "Failed to connect to Microsoft Graph." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit
}


# ============================================================
# Retrieve Universal Print printers
# ============================================================

Write-Host ""
Write-Host "Retrieving Universal Print printers..." -ForegroundColor Cyan

try {

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/print/printers" `
        -ErrorAction Stop

    $Printers = @($Response.value)

    while ($Response.'@odata.nextLink') {

        $Response = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $Response.'@odata.nextLink' `
            -ErrorAction Stop

        $Printers += @($Response.value)
    }
}
catch {

    Write-Host ""
    Write-Host "Failed to retrieve Universal Print printers." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    Disconnect-GraphSafely

    exit
}

Write-Host ""
Write-Host
# ============================================================
# Match CSV against Universal Print
# ============================================================

$Validation = @()

foreach ($Row in $CsvData) {

    $PrinterMatches = @(
        $Printers |
        Where-Object {
            $_.displayName -eq $Row.PrinterName
        }
    )

    if ($PrinterMatches.Count -eq 1) {

        $Validation += [PSCustomObject]@{
            PrinterName = $Row.PrinterName
            Status      = "Found"
            PrinterId   = $PrinterMatches[0].id
        }
    }
    elseif ($PrinterMatches.Count -eq 0) {

        $Validation += [PSCustomObject]@{
            PrinterName = $Row.PrinterName
            Status      = "Not Found"
            PrinterId   = ""
        }
    }
    else {

        $Validation += [PSCustomObject]@{
            PrinterName = $Row.PrinterName
            Status      = "Multiple Matches"
            PrinterId   = ""
        }
    }
}


# ============================================================
# Show validation
# ============================================================

Write-Host ""
Write-Host "CSV validation:" -ForegroundColor Cyan
Write-Host ""

$Validation |
    Sort-Object PrinterName |
    Format-Table PrinterName, Status -AutoSize

$FoundCount = @(
    $Validation |
    Where-Object {
        $_.Status -eq "Found"
    }
).Count

$NotFoundCount = @(
    $Validation |
    Where-Object {
        $_.Status -eq "Not Found"
    }
).Count

$MultipleCount = @(
    $Validation |
    Where-Object {
        $_.Status -eq "Multiple Matches"
    }
).Count

Write-Host ""
Write-Host "CSV printers:     $($CsvData.Count)"
Write-Host "Matched:          $FoundCount" -ForegroundColor Green

if ($NotFoundCount -gt 0) {
    Write-Host "Not found:        $NotFoundCount" -ForegroundColor Yellow
}
else {
    Write-Host "Not found:        $NotFoundCount" -ForegroundColor Green
}

if ($MultipleCount -gt 0) {
    Write-Host "Multiple matches: $MultipleCount" -ForegroundColor Yellow
}
else {
    Write-Host "Multiple matches: $MultipleCount" -ForegroundColor Green
}


# ============================================================
# Stop if no printers matched
# ============================================================

if ($FoundCount -eq 0) {

    Write-Host ""
    Write-Host "No printers can be updated." -ForegroundColor Red

    Disconnect-GraphSafely

    exit
}


# ============================================================
# Final confirmation
# ============================================================

Write-Host ""
Write-Host "$FoundCount printer(s) will be updated." -ForegroundColor Yellow

if ($NotFoundCount -gt 0) {
    Write-Host "$NotFoundCount printer(s) were not found and will be skipped." -ForegroundColor Yellow
}

if ($MultipleCount -gt 0) {
    Write-Host "$MultipleCount printer(s) have multiple matches and will be skipped." -ForegroundColor Yellow
}

Write-Host ""

$Confirmation = Read-Host "Type YES to start the bulk update"

if ($Confirmation.Trim() -ine "YES") {

    Write-Host ""
    Write-Host "Operation cancelled." -ForegroundColor Yellow

    Disconnect-GraphSafely

    exit
}


# ============================================================
# Update printers
# ============================================================

$Results = @()
$Counter = 0

foreach ($Row in $CsvData) {

    $Match = @(
        $Validation |
        Where-Object {
            $_.PrinterName -eq $Row.PrinterName -and
            $_.Status -eq "Found"
        }
    )

    if ($Match.Count -ne 1) {
        continue
    }

    $Counter++

    Write-Host ""
    Write-Host "[$Counter/$FoundCount] $($Row.PrinterName)" -ForegroundColor Cyan

    try {

        $Location = @{}

        Add-DoubleProperty `
            -Target $Location `
            -Name "latitude" `
            -Value $Row.Latitude

        Add-DoubleProperty `
            -Target $Location `
            -Name "longitude" `
            -Value $Row.Longitude

        Add-IntegerProperty `
            -Target $Location `
            -Name "altitudeInMeters" `
            -Value $Row.AltitudeInMeters

        Add-CollectionProperty `
            -Target $Location `
            -Name "organization" `
            -Value $Row.Organization

        Add-CollectionProperty `
            -Target $Location `
            -Name "subdivision" `
            -Value $Row.Subdivision

        Add-StringProperty `
            -Target $Location `
            -Name "site" `
            -Value $Row.Site

        Add-CollectionProperty `
            -Target $Location `
            -Name "subUnit" `
            -Value $Row.SubUnit

        Add-StringProperty `
            -Target $Location `
            -Name "building" `
            -Value $Row.Building

        Add-StringProperty `
            -Target $Location `
            -Name "floor" `
            -Value $Row.Floor

        Add-StringProperty `
            -Target $Location `
            -Name "floorDescription" `
            -Value $Row.FloorDescription

        Add-StringProperty `
            -Target $Location `
            -Name "roomName" `
            -Value $Row.RoomName

        Add-StringProperty `
            -Target $Location `
            -Name "roomDescription" `
            -Value $Row.RoomDescription

        Add-StringProperty `
            -Target $Location `
            -Name "streetAddress" `
            -Value $Row.StreetAddress

        Add-StringProperty `
            -Target $Location `
            -Name "city" `
            -Value $Row.City

        Add-StringProperty `
            -Target $Location `
            -Name "stateOrProvince" `
            -Value $Row.StateOrProvince

        Add-StringProperty `
            -Target $Location `
            -Name "postalCode" `
            -Value $Row.PostalCode

        Add-StringProperty `
            -Target $Location `
            -Name "countryOrRegion" `
            -Value $Row.CountryOrRegion

        if ($Location.Count -eq 0) {
            throw "No location properties are configured for this printer."
        }

        $BodyObject = @{
            location = $Location
        }

        $Body = $BodyObject | ConvertTo-Json -Depth 10

        Invoke-MgGraphRequest `
            -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/print/printers/$($Match[0].PrinterId)" `
            -Body $Body `
            -ContentType "application/json" `
            -ErrorAction Stop |
            Out-Null

        Write-Host "Updated successfully." -ForegroundColor Green

        $Results += [PSCustomObject]@{
            PrinterName = $Row.PrinterName
            PrinterId   = $Match[0].PrinterId
            Result      = "Success"
            Error       = ""
        }
    }
    catch {

        Write-Host "Update failed." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        $Results += [PSCustomObject]@{
            PrinterName = $Row.PrinterName
            PrinterId   = $Match[0].PrinterId
            Result      = "Failed"
            Error       = $_.Exception.Message
        }
    }
}


# ============================================================
# Add skipped printers to results
# ============================================================

$SkippedEntries = @(
    $Validation |
    Where-Object {
        $_.Status -ne "Found"
    }
)

foreach ($SkippedEntry in $SkippedEntries) {

    $Results += [PSCustomObject]@{
        PrinterName = $SkippedEntry.PrinterName
        PrinterId   = ""
        Result      = "Skipped"
        Error       = $SkippedEntry.Status
    }
}


# ============================================================
# Summary
# ============================================================

$Successful = @(
    $Results |
    Where-Object {
        $_.Result -eq "Success"
    }
).Count

$Failed = @(
    $Results |
    Where-Object {
        $_.Result -eq "Failed"
    }
).Count

$SkippedCount = @(
    $Results |
    Where-Object {
        $_.Result -eq "Skipped"
    }
).Count

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Universal Print Location Update completed"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Successful: $Successful" -ForegroundColor Green

if ($Failed -gt 0) {
    Write-Host "Failed:     $Failed" -ForegroundColor Red
}
else {
    Write-Host "Failed:     $Failed" -ForegroundColor Green
}

if ($SkippedCount -gt 0) {
    Write-Host "Skipped:    $SkippedCount" -ForegroundColor Yellow
}
else {
    Write-Host "Skipped:    $SkippedCount" -ForegroundColor Green
}


# ============================================================
# Optional result log export
# ============================================================

$LogPath = $null

Write-Host ""

$ExportLog = Read-Host "Do you want to export a result log? (YES/NO)"

if ($ExportLog.Trim() -ieq "YES") {

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog

    $SaveDialog.Title = "Save Universal Print Location Update Log"
    $SaveDialog.Filter = "CSV files (*.csv)|*.csv"
    $SaveDialog.FileName = "UniversalPrint_LocationUpdate_$Timestamp.csv"
    $SaveDialog.DefaultExt = "csv"
    $SaveDialog.AddExtension = $true
    $SaveDialog.OverwritePrompt = $true
    $SaveDialog.CheckPathExists = $true
    $SaveDialog.RestoreDirectory = $true

    $SaveResult = $SaveDialog.ShowDialog()

    if ($SaveResult -eq [System.Windows.Forms.DialogResult]::OK) {

        $LogPath = $SaveDialog.FileName

        try {

            $Results |
                Sort-Object PrinterName |
                Export-Csv `
                    -Path $LogPath `
                    -Delimiter ";" `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -ErrorAction Stop

            Write-Host ""
            Write-Host "Result log successfully exported." -ForegroundColor Green
            Write-Host "Location:" -ForegroundColor Cyan
            Write-Host $LogPath
        }
        catch {

            Write-Host ""
            Write-Host "Failed to export the result log." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red

            $LogPath = $null
        }
    }
    else {

        Write-Host ""
        Write-Host "Log export cancelled. No log file was created." -ForegroundColor Yellow
    }
}
else {

    Write-Host ""
    Write-Host "Log export skipped. No log file was created." -ForegroundColor Yellow
}


# ============================================================
# Disconnect Microsoft Graph
# ============================================================

Write-Host ""
Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Cyan

Disconnect-GraphSafely

Write-Host "Done." -ForegroundColor Green