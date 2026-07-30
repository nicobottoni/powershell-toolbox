<#
.SYNOPSIS
    Export/View CA Accounts and Group Memberships.

.DESCRIPTION
    Retrieves CA Accounts from Active Directory and provides:

    - Overview
    - CSV Export
    - Statistics

    The search base OU is selected interactively during runtime.
    Change $ADFilter as needed

.NOTES
    Author  : Nico Bottoni
    

.REQUIREMENTS
    ActiveDirectory PowerShell Module

.EXAMPLE
    .\Export_CAUser_MemberOfGroups.ps1
#>

#Requires -Modules ActiveDirectory
#Requires -Version 5.1

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------

$ScriptVersion = "1.0.0"

$Config = @{
    ExportPath = Join-Path $PSScriptRoot "Exports"
}

$ADFilter = {
    Description -eq "3289 CA-Account" -and
    SamAccountName -like "CA*"
}

# ---------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------

function Write-Log {

    param(
        [string]$Message,

        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    switch ($Level) {

        'INFO'    { $Color = 'Cyan' }
        'SUCCESS' { $Color = 'Green' }
        'WARNING' { $Color = 'Yellow' }
        'ERROR'   { $Color = 'Red' }

    }

    Write-Host "[$Level] $Message" -ForegroundColor $Color
}

function New-ExportFolder {

    if (-not (Test-Path $Config.ExportPath)) {

        New-Item `
            -Path $Config.ExportPath `
            -ItemType Directory `
            -Force | Out-Null
    }
}

function Get-SearchBase {

    while ($true) {

        Write-Host ""
        Write-Host "Enter Search Base OU" -ForegroundColor Cyan
        Write-Host "Example: OU=Companies,DC=contoso,DC=com"
        Write-Host ""

        $SearchBase = Read-Host "Search Base"

        try {

            Get-ADOrganizationalUnit `
                -Identity $SearchBase `
                -ErrorAction Stop | Out-Null

            Write-Log "Using Search Base: $SearchBase" SUCCESS

            return $SearchBase
        }
        catch {

            Write-Log "OU not found." ERROR

        }
    }
}

function Get-CAAccounts {

    param(
        [Parameter(Mandatory)]
        [string]$SearchBase
    )

    Write-Log "Reading CA Accounts..."

    $Results = foreach ($User in Get-ADUser `
        -Filter $ADFilter `
        -SearchBase $SearchBase `
        -Properties MemberOf) {

        if ($User.MemberOf) {

            foreach ($GroupDN in $User.MemberOf) {

                try {

                    $Group = Get-ADGroup `
                        -Identity $GroupDN `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        SamAccountName = $User.SamAccountName
                        DisplayName    = $User.Name
                        GroupName      = $Group.SamAccountName
                    }
                }
                catch {

                    Write-Log "Could not read group: $GroupDN" WARNING

                }
            }
        }
        else {

            [PSCustomObject]@{
                SamAccountName = $User.SamAccountName
                DisplayName    = $User.Name
                GroupName      = "<No Group Membership>"
            }
        }
    }

    return $Results
}

function Show-Overview {

    $SearchBase = Get-SearchBase

    $Data = @(Get-CAAccounts `
        -SearchBase $SearchBase)

    $Data | Out-GridView -Title "CA Account Membership Overview"

    Write-Log "$($Data.Count) entries found." SUCCESS

    Write-Host ""
    Read-Host "Press Enter to return to the main menu"
}

function Export-Report {

    $SearchBase = Get-SearchBase

    New-ExportFolder

    $Data = Get-CAAccounts `
        -SearchBase $SearchBase

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $FilePath = Join-Path `
        $Config.ExportPath `
        "CAAccountMembershipReport_$Timestamp.csv"

    $Data | Export-Csv `
        -Path $FilePath `
        -NoTypeInformation `
        -Encoding UTF8

    Write-Log "Export completed." SUCCESS
    Write-Log "File: $FilePath" INFO
}

function Show-Statistics {

    $SearchBase = Get-SearchBase

    $Users = @(Get-ADUser `
        -Filter $ADFilter `
        -SearchBase $SearchBase)

    Write-Host ""
    Write-Host "============================================="
    Write-Host "Statistics"
    Write-Host "============================================="
    Write-Host ""
    Write-Host "CA Accounts Found : $($Users.Count)"
    Write-Host ""

    Pause
}

function Show-Menu {

    Clear-Host

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "      CA Account Reporting Tool v$ScriptVersion"
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1 - Show Overview"
    Write-Host "2 - Create CSV Export"
    Write-Host "3 - View Statistics"
    Write-Host "Q - Exit"
    Write-Host ""

    Read-Host "Selection"
}

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

$ExitScript = $false

do {

    $Choice = Show-Menu

    switch ($Choice.ToUpper()) {

        "1" {

            Show-Overview
        }

        "2" {

            Export-Report
            Pause
        }

        "3" {

            Show-Statistics
        }

        "Q" {

            $ExitScript = $true
        }

        default {

            Write-Log "Invalid selection." ERROR
            Start-Sleep -Seconds 2
        }
    }

}
while (-not $ExitScript)

Write-Log "Script terminated." INFO