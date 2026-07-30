<#
.SYNOPSIS
Exports Windows Eventlog for Login, Lock and Unlock Events

.DESCRIPTION
Helps to keep track of working hours

.EXAMPLE
.\ClientLocktime.ps1
 
.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: DailyBusiness
Created: 2026-07-10
Last Updated: XXXX-XX-XX
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