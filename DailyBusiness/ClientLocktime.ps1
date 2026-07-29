<#
.SYNOPSIS
Exports Active Directory SamAccountNames based on email addresses from a CSV file

.DESCRIPTION
Imports a CSV file containing email addresses and searches Active Directory for matching users.
For each matching user, the script exports the email address and corresponding SamAccountName
to a CSV file.

The input CSV file must contain a column named "email".

.PARAMETER OutputPath
Defines the directory where the output CSV file will be written.
 
.PARAMETER OutputFileName
Defines the name of the output CSV file.

.EXAMPLE
.\Get-SamAccountNameFromEmail.ps1
 
.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: ActiveDirectory/Users
Created: 2024-02-01
Last Updated: 2025-11-11
#>

$StartTime = (Get-Date).Date

$Events = @()

# Anmeldung
$Events += Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    ProviderName = 'Microsoft-Windows-Winlogon'
    Id           = 7001
    StartTime    = $StartTime
} | Select-Object TimeCreated,
@{
    Name='Status'
    Expression={'Logon'}
}

# Sperren / Entsperren
$Events += Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4800,4801
    StartTime = $StartTime
} | Select-Object TimeCreated,
@{
    Name='Status'
    Expression={
        if ($_.Id -eq 4800) {
            'Locked'
        } else {
            'Unlocked'
        }
    }
}

$Events |
Sort-Object TimeCreated |
Format-Table -AutoSize