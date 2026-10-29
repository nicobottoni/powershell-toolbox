#requires -Version 5.1
#requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Copies direct Active Directory group memberships from a source user
    to a target user.

.DESCRIPTION
    - Interactive input for source and target user
    - Validates both users before making changes
    - Copies direct AD group memberships only
    - Existing memberships are skipped
    - Errors are handled individually per group
    - Failed groups are displayed at the end together with the reason
    - Optional CSV export of the complete result

.NOTES
    The script does NOT remove any existing group memberships from
    the target user.

    The user's primary group, normally "Domain Users", is not part of
    the MemberOf attribute and is therefore not copied.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function Write-Section {

    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    Write-Host
    Write-Host ('=' * 70) -ForegroundColor DarkGray
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor DarkGray
}


function Get-InteractiveADUser {

    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [string]$Role
    )

    while ($true) {

        $Identity = Read-Host $Prompt

        if ([string]::IsNullOrWhiteSpace($Identity)) {
            Write-Warning 'The input cannot be empty.'
            continue
        }

        try {

            $User = Get-ADUser `
                -Identity $Identity.Trim() `
                -Properties DisplayName, MemberOf, UserPrincipalName, Enabled `
                -ErrorAction Stop

            Write-Host
            Write-Host "$Role found:" -ForegroundColor Green
            Write-Host "  Display Name : $($User.DisplayName)"
            Write-Host "  User Name    : $($User.SamAccountName)"
            Write-Host "  UPN          : $($User.UserPrincipalName)"
            Write-Host "  Enabled      : $($User.Enabled)"
            Write-Host "  Direct Groups: $(@($User.MemberOf).Count)"
            Write-Host

            return $User
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {

            Write-Warning "User '$Identity' was not found."
        }
        catch {

            Write-Warning "User '$Identity' could not be retrieved."
            Write-Warning $_.Exception.Message
        }
    }
}


function Get-FriendlyFailureReason {

    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Message = $ErrorRecord.Exception.Message

    if ($Message -match 'access.*denied|insufficient access rights|Zugriff.*verweigert|unzureichende Zugriffsrechte') {

        return "Insufficient permissions to modify this group. AD message: $Message"
    }

    if ($Message -match 'cannot find|not found|nicht gefunden|kein Objekt') {

        return "The group or target user could not be resolved. AD message: $Message"
    }

    if ($Message -match 'already a member|bereits.*Mitglied') {

        return "The target user is already a member of this group. AD message: $Message"
    }

    if ($Message -match 'server is unwilling|nicht bereit|unwilling to process') {

        return "The domain controller rejected the modification. AD message: $Message"
    }

    if ($Message -match 'constraint|Einschränkung|constraint violation') {

        return "Active Directory rejected the modification because of a directory constraint. AD message: $Message"
    }

    if ($Message -match 'referral|Verweis') {

        return "Active Directory returned a referral. The group may belong to another domain. AD message: $Message"
    }

    return $Message
}


# ------------------------------------------------------------
# Load Active Directory module
# ------------------------------------------------------------

try {

    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {

    Write-Error @"
The ActiveDirectory PowerShell module could not be loaded.

Make sure the Active Directory RSAT tools are installed.

Technical error:
$($_.Exception.Message)
"@

    return
}


# ------------------------------------------------------------
# User selection
# ------------------------------------------------------------

Clear-Host

Write-Host 'Active Directory Group Membership Copy Tool' -ForegroundColor Cyan
Write-Host '-------------------------------------------' -ForegroundColor DarkGray
Write-Host
Write-Host 'Press Ctrl+C at any time to cancel.' -ForegroundColor DarkGray


Write-Section '1. Select Users'


$SourceUser = Get-InteractiveADUser `
    -Prompt 'Enter SOURCE user (User A)' `
    -Role 'Source user'


do {

    $TargetUser = Get-InteractiveADUser `
        -Prompt 'Enter TARGET user (User B)' `
        -Role 'Target user'

    if ($SourceUser.DistinguishedName -eq $TargetUser.DistinguishedName) {

        Write-Warning 'Source and target user cannot be identical.'
    }

}
while ($SourceUser.DistinguishedName -eq $TargetUser.DistinguishedName)


# ------------------------------------------------------------
# Read group memberships
# ------------------------------------------------------------

Write-Section '2. Analyse Group Memberships'


$SourceGroupDNs = @(
    $SourceUser.MemberOf |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
)


$TargetGroupDNs = @(
    $TargetUser.MemberOf |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)


if ($SourceGroupDNs.Count -eq 0) {

    Write-Warning "Source user '$($SourceUser.SamAccountName)' has no direct group memberships."

    return
}


# Create case-insensitive lookup for memberships already existing
# on the target user.

$TargetMemberships = New-Object `
    'System.Collections.Generic.HashSet[string]' `
    ([System.StringComparer]::OrdinalIgnoreCase)


foreach ($GroupDN in $TargetGroupDNs) {

    [void]$TargetMemberships.Add($GroupDN)
}


# Resolve groups individually.
# This also allows read errors to be captured without stopping
# the complete process.

$GroupsToProcess = @(

    foreach ($GroupDN in $SourceGroupDNs) {

        try {

            Get-ADGroup `
                -Identity $GroupDN `
                -Properties Name, SamAccountName, GroupCategory, GroupScope `
                -ErrorAction Stop
        }
        catch {

            [PSCustomObject]@{
                Name              = $GroupDN
                SamAccountName    = $null
                DistinguishedName = $GroupDN
                GroupCategory     = $null
                GroupScope        = $null
                ReadError         = $_.Exception.Message
            }
        }
    }
)


$AlreadyMember = @(
    $GroupsToProcess |
        Where-Object {
            $TargetMemberships.Contains($_.DistinguishedName)
        }
)


$GroupsToAdd = @(
    $GroupsToProcess |
        Where-Object {
            -not $TargetMemberships.Contains($_.DistinguishedName)
        }
)


# ------------------------------------------------------------
# Summary before execution
# ------------------------------------------------------------

Write-Host "Source user          : $($SourceUser.DisplayName) [$($SourceUser.SamAccountName)]"
Write-Host "Target user          : $($TargetUser.DisplayName) [$($TargetUser.SamAccountName)]"
Write-Host

Write-Host "Source groups        : $($GroupsToProcess.Count)"
Write-Host "Already assigned     : $($AlreadyMember.Count)"
Write-Host "Groups to be added   : $($GroupsToAdd.Count)" -ForegroundColor Yellow
Write-Host


if ($GroupsToAdd.Count -eq 0) {

    Write-Host 'The target user is already a member of all direct groups of the source user.' -ForegroundColor Green

    return
}


Write-Host 'The following groups will be processed:' -ForegroundColor Cyan
Write-Host


$GroupsToAdd |
    Sort-Object Name |
    Select-Object Name,
                  SamAccountName,
                  GroupCategory,
                  GroupScope |
    Format-Table -AutoSize


# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

Write-Host

$Confirmation = Read-Host "Continue? Type 'YES' to add the memberships"


if ($Confirmation -ine 'YES') {

    Write-Warning 'Operation cancelled. No changes were made.'

    return
}


# ------------------------------------------------------------
# Process memberships
# ------------------------------------------------------------

Write-Section '3. Add Group Memberships'


$Results = [System.Collections.Generic.List[object]]::new()


# Add memberships which already existed to the report.

foreach ($Group in $AlreadyMember) {

    $Results.Add(

        [PSCustomObject]@{
            GroupName       = $Group.Name
            SamAccountName  = $Group.SamAccountName
            GroupScope      = $Group.GroupScope
            Status          = 'Already Member'
            Successful      = $true
            Reason          = 'Target user was already a member of this group.'
        }
    )
}


$CurrentNumber = 0


foreach ($Group in $GroupsToAdd) {

    $CurrentNumber++


    if (-not [string]::IsNullOrWhiteSpace($Group.Name)) {

        $DisplayGroupName = $Group.Name
    }
    else {

        $DisplayGroupName = $Group.DistinguishedName
    }


    Write-Host "[$CurrentNumber/$($GroupsToAdd.Count)] $DisplayGroupName" -NoNewline


    # Check whether the group itself could be read.

    if (
        ($Group.PSObject.Properties.Name -contains 'ReadError') -and
        (-not [string]::IsNullOrWhiteSpace($Group.ReadError))
    ) {

        Write-Host ' [FAILED]' -ForegroundColor Red


        $Results.Add(

            [PSCustomObject]@{
                GroupName       = $DisplayGroupName
                SamAccountName  = $Group.SamAccountName
                GroupScope      = $Group.GroupScope
                Status          = 'Failed'
                Successful      = $false
                Reason          = "The group could not be read: $($Group.ReadError)"
            }
        )


        continue
    }


    try {

        Add-ADGroupMember `
            -Identity $Group.DistinguishedName `
            -Members $TargetUser.DistinguishedName `
            -Confirm:$false `
            -ErrorAction Stop


        Write-Host ' [OK]' -ForegroundColor Green


        $Results.Add(

            [PSCustomObject]@{
                GroupName       = $Group.Name
                SamAccountName  = $Group.SamAccountName
                GroupScope      = $Group.GroupScope
                Status          = 'Added'
                Successful      = $true
                Reason          = 'Group membership was successfully added.'
            }
        )
    }
    catch {

        $Reason = Get-FriendlyFailureReason `
            -ErrorRecord $_


        Write-Host ' [FAILED]' -ForegroundColor Red
        Write-Host "    $Reason" -ForegroundColor DarkRed


        $Results.Add(

            [PSCustomObject]@{
                GroupName       = $Group.Name
                SamAccountName  = $Group.SamAccountName
                GroupScope      = $Group.GroupScope
                Status          = 'Failed'
                Successful      = $false
                Reason          = $Reason
            }
        )
    }
}


# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

Write-Section '4. Result'


$AddedGroups = @(
    $Results |
        Where-Object { $_.Status -eq 'Added' }
)


$ExistingGroups = @(
    $Results |
        Where-Object { $_.Status -eq 'Already Member' }
)


$FailedGroups = @(
    $Results |
        Where-Object { $_.Status -eq 'Failed' }
)


Write-Host "Successfully added : $($AddedGroups.Count)" -ForegroundColor Green
Write-Host "Already member     : $($ExistingGroups.Count)" -ForegroundColor Gray


if ($FailedGroups.Count -gt 0) {

    Write-Host "Failed             : $($FailedGroups.Count)" -ForegroundColor Red
}
else {

    Write-Host "Failed             : 0" -ForegroundColor Green
}


# ------------------------------------------------------------
# Display failed groups
# ------------------------------------------------------------

if ($FailedGroups.Count -gt 0) {

    Write-Host
    Write-Host 'Groups that could NOT be assigned:' -ForegroundColor Red
    Write-Host


    $FailedGroups |
        Sort-Object GroupName |
        Select-Object GroupName,
                      SamAccountName,
                      GroupScope,
                      Reason |
        Format-Table -Wrap -AutoSize
}
else {

    Write-Host
    Write-Host 'All required group memberships were processed successfully.' -ForegroundColor Green
}


# ---------------------------------------------------------------------
# Optional CSV export
# ---------------------------------------------------------------------

Write-Host
$ExportAnswer = Read-Host "Export the complete result to CSV? Type 'YES'"

if ($ExportAnswer.Trim() -ieq 'YES') {

    $TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $DefaultFileName = "AD_GroupCopy_$($SourceUser.SamAccountName)_to_$($TargetUser.SamAccountName)_$TimeStamp.csv"

    Add-Type -AssemblyName System.Windows.Forms

    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Title = "Save Group Membership Report"
    $SaveFileDialog.Filter = "CSV files (*.csv)|*.csv"
    $SaveFileDialog.FileName = $DefaultFileName
    $SaveFileDialog.DefaultExt = "csv"
    $SaveFileDialog.AddExtension = $true
    $SaveFileDialog.OverwritePrompt = $true

    if ($SaveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {

        try {
            $Results |
                Sort-Object Status, Group |
                Export-Csv `
                    -Path $SaveFileDialog.FileName `
                    -Delimiter ';' `
                    -Encoding UTF8 `
                    -NoTypeInformation

            Write-Host
            Write-Host "CSV successfully exported:" -ForegroundColor Green
            Write-Host $SaveFileDialog.FileName -ForegroundColor Green
        }
        catch {
            Write-Warning "CSV export failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host
        Write-Host "CSV export cancelled." -ForegroundColor Yellow
    }
}
else {
    Write-Host
    Write-Host "CSV export skipped." -ForegroundColor DarkGray
}

Write-Host
Write-Host 'Operation completed.' -ForegroundColor Cyan