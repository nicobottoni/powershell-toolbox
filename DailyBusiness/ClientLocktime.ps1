<#
.SYNOPSIS
Displays logon, lock and unlock events for the current day.

.DESCRIPTION
Queries the Windows Security Event Log and returns user logon,
workstation lock and workstation unlock events that occurred today.

.EXAMPLE
.\Get-ClientLockActivity.ps1

.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: WindowsAdministration/EventLogs
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