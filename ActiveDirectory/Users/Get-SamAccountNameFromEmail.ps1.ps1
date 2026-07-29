<#
.SYNOPSIS
Exports Active Directory SamAccountNames based on email addresses from a CSV file.

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

Prompts for a CSV file and exports the matching SamAccountNames to the default output path.

.EXAMPLE
.\Get-SamAccountNameFromEmail.ps1 -OutputPath "C:\Temp" -OutputFileName "SamAccountNames.csv"

Prompts for a CSV file and writes the result to C:\Temp\SamAccountNames.csv.

.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: ActiveDirectory/Users
Created: 2024-02-01
Last Updated: 2025-11-11
#>

# Output configuration
$Path = 'C:\Management\Scripts\SamAccountNameFromEmail'
$OutputCSV = 'SamAccountNames_output.csv'

# Select input CSV file
Write-Host "Please select your CSV file. CSV header must be like this:"
Write-Host "email"

[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null

$FileDialog = New-Object System.Windows.Forms.OpenFileDialog
$FileDialog.Filter = "CSV files (*.csv)|*.csv"
$FileDialog.ShowHelp = $true
$FileDialog.ShowDialog() | Out-Null

# Store selected file path
$ImpFile = $FileDialog.FileName

# Import CSV file
$Emails = Import-Csv $ImpFile

# Generate SamAccountNames from email addresses
$Results = foreach ($Email in $Emails.Email) {
    $User = Get-ADUser -Filter { EmailAddress -eq $Email } -ErrorAction SilentlyContinue

    if ($User) {
        [PSCustomObject]@{
            Email          = $Email
            SamAccountName = $User.SamAccountName
        }
    }
    else {
        Write-Warning "No user found with the e-mail address: $Email"
    }
}

# Export results
$Results | Export-Csv -Path "$Path\$OutputCSV" -NoTypeInformation

Write-Host "SamAccountNames were written together with the e-mail addresses to: $OutputCSV"