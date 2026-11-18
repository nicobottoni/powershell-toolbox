<#
.SYNOPSIS
    Checks whether users from an input file are members of a specified Active Directory group.

.DESCRIPTION
    Opens a Windows file selection dialog to select a text file containing user accounts
    and compares those accounts against the membership of a specified Active Directory group.

    Group membership is retrieved once from Active Directory and stored in a case-insensitive
    HashSet for fast local lookups. This avoids performing an Active Directory query for every
    individual user and provides efficient processing for large environments.

    The input file must contain one sAMAccountName per line.

    The resulting CSV report is automatically saved in the same directory as the selected
    input file.

.NOTES
    Author: Nico Bottoni
    Created: 03.02.2023
    Last Modified: 18.11.2026

    Requirements:
    - Windows PowerShell 5.1 or PowerShell 7+
    - ActiveDirectory PowerShell module
    - Windows environment for the graphical file selection dialog

.EXAMPLE
    .\Get-ADGroupMembershipReport.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

function Show-FileSelectionDialog {

    try {
        Add-Type -AssemblyName System.Windows.Forms
    }
    catch {
        throw "Unable to load System.Windows.Forms."
    }

    $FileDialog = New-Object System.Windows.Forms.OpenFileDialog

    $FileDialog.Title = 'Select User List'
    $FileDialog.Filter = 'Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    $FileDialog.FilterIndex = 1
    $FileDialog.Multiselect = $false
    $FileDialog.CheckFileExists = $true
    $FileDialog.CheckPathExists = $true

    $Result = $FileDialog.ShowDialog()

    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    return $FileDialog.FileName
}

function Read-GroupName {

    do {

        $GroupName = Read-Host 'Enter the Active Directory group name'

        if ([string]::IsNullOrWhiteSpace($GroupName)) {
            Write-Host 'A group name must be specified.' -ForegroundColor Yellow
        }

    } until (-not [string]::IsNullOrWhiteSpace($GroupName))

    return $GroupName.Trim()
}

function Read-RecursiveChoice {

    do {

        $Choice = Read-Host 'Include nested group membership? (Y/N)'

        switch ($Choice.Trim().ToUpperInvariant()) {

            'Y' {
                return $true
            }

            'N' {
                return $false
            }

            default {
                Write-Host 'Please enter Y or N.' -ForegroundColor Yellow
            }
        }

    } while ($true)
}

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

Clear-Host

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkGray
Write-Host ' Active Directory Group Membership Report' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------
# Check Active Directory module
# ------------------------------------------------------------

Write-Host 'Checking prerequisites...' -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {

    Write-Host ''
    Write-Host 'ERROR: The ActiveDirectory PowerShell module is not available.' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Install the Active Directory PowerShell module and try again.'
    Write-Host ''

    return
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {

    Write-Host ''
    Write-Host 'ERROR: The ActiveDirectory PowerShell module could not be loaded.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    return
}

Write-Host 'ActiveDirectory module loaded successfully.' -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------
# Select input file
# ------------------------------------------------------------

Write-Host 'Select the user list...' -ForegroundColor Yellow

try {
    $ImportFile = Show-FileSelectionDialog
}
catch {

    Write-Host ''
    Write-Host 'ERROR: Unable to open the file selection dialog.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    return
}

if ([string]::IsNullOrWhiteSpace($ImportFile)) {

    Write-Host ''
    Write-Host 'No file selected. Operation cancelled.' -ForegroundColor Yellow
    Write-Host ''

    return
}

Write-Host ''
Write-Host 'Selected file:' -ForegroundColor DarkGray
Write-Host $ImportFile -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------
# Read group information
# ------------------------------------------------------------

$GroupName = Read-GroupName
$Recursive = Read-RecursiveChoice

Write-Host ''

# ------------------------------------------------------------
# Validate Active Directory group
# ------------------------------------------------------------

Write-Host "Validating group '$GroupName'..." -ForegroundColor Yellow

try {

    $ADGroup = Get-ADGroup `
        -Identity $GroupName `
        -Properties DistinguishedName `
        -ErrorAction Stop
}
catch {

    Write-Host ''
    Write-Host "ERROR: Active Directory group '$GroupName' could not be found." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    return
}

Write-Host 'Group found successfully.' -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------
# Import user list
# ------------------------------------------------------------

Write-Host 'Importing user list...' -ForegroundColor Yellow

try {

    $Users = @(
        Get-Content -LiteralPath $ImportFile -ErrorAction Stop |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } |
        Sort-Object -Unique
    )
}
catch {

    Write-Host ''
    Write-Host 'ERROR: Unable to read the selected user list.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    return
}

if ($Users.Count -eq 0) {

    Write-Host ''
    Write-Host 'The selected file does not contain any users.' -ForegroundColor Yellow
    Write-Host ''

    return
}

Write-Host "$($Users.Count) unique user(s) imported." -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------
# Retrieve group membership
# ------------------------------------------------------------

Write-Host 'Reading Active Directory group membership...' -ForegroundColor Yellow

try {

    $GroupMemberParameters = @{
        Identity    = $ADGroup.DistinguishedName
        ErrorAction = 'Stop'
    }

    if ($Recursive) {
        $GroupMemberParameters['Recursive'] = $true
    }

    $Members = @(
        Get-ADGroupMember @GroupMemberParameters |
        Where-Object {
            $_.ObjectClass -eq 'user'
        } |
        Select-Object -ExpandProperty SamAccountName
    )
}
catch {

    Write-Host ''
    Write-Host "ERROR: Unable to read members of group '$GroupName'." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    return
}

Write-Host "$($Members.Count) user member(s) found." -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------
# Build high-performance membership lookup
# ------------------------------------------------------------

Write-Host 'Building membership lookup...' -ForegroundColor Yellow

$MemberLookup = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($Member in $Members) {

    if (-not [string]::IsNullOrWhiteSpace($Member)) {
        [void]$MemberLookup.Add($Member)
    }
}

Write-Host 'Membership lookup created.' -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------
# Check users
# ------------------------------------------------------------

Write-Host 'Checking user memberships...' -ForegroundColor Yellow

$Results = @(
    foreach ($User in $Users) {

        [PSCustomObject]@{
            Username  = $User
            IsInGroup = $MemberLookup.Contains($User)
        }
    }
)

Write-Host 'Membership check completed.' -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------
# Create export path
# ------------------------------------------------------------

$ImportDirectory = Split-Path -Path $ImportFile -Parent
$SafeGroupName = $GroupName -replace '[\\/:*?"<>|]', '_'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$ExportFile = Join-Path `
    -Path $ImportDirectory `
    -ChildPath "AD_GroupMembership_${SafeGroupName}_${Timestamp}.csv"

# ------------------------------------------------------------
# Export results
# ------------------------------------------------------------

Write-Host 'Creating CSV report...' -ForegroundColor Yellow

try {

    $Results |
        Export-Csv `
            -LiteralPath $ExportFile `
            -Delimiter ';' `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force
}
catch {

    Write-Host ''
    Write-Host 'ERROR: Unable to create the CSV report.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    return
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

$UsersChecked = $Results.Count

$MembersFound = @(
    $Results | Where-Object {
        $_.IsInGroup -eq $true
    }
).Count

$MembersMissing = $UsersChecked - $MembersFound

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkGray
Write-Host ' Membership Check Completed' -ForegroundColor Green
Write-Host '=============================================' -ForegroundColor DarkGray
Write-Host ''

Write-Host 'Group            : ' -NoNewline
Write-Host $GroupName -ForegroundColor Cyan

Write-Host 'Recursive        : ' -NoNewline
Write-Host $Recursive -ForegroundColor Cyan

Write-Host 'Users checked    : ' -NoNewline
Write-Host $UsersChecked -ForegroundColor Cyan

Write-Host 'Members          : ' -NoNewline
Write-Host $MembersFound -ForegroundColor Green

Write-Host 'Not members      : ' -NoNewline
Write-Host $MembersMissing -ForegroundColor Yellow

Write-Host ''
Write-Host 'Report saved to:' -ForegroundColor DarkGray
Write-Host $ExportFile -ForegroundColor Cyan
Write-Host ''