<#
.SYNOPSIS
Finds empty folders under a selected path and deletes them after one confirmation.

.DESCRIPTION
Recursively scans a local path or UNC share for empty folders. Before deleting,
each candidate is checked again to ensure it still exists and is empty. Successful
deletions are recorded in a timestamped CSV log next to this script.

Requires PowerShell 7 or newer. Windows PowerShell 5.1 will relaunch this script
in PowerShell 7 if pwsh.exe is installed.

.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: Filesystem
#>

# Relaunch with PowerShell 7 when started from Windows PowerShell 5.1.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $PowerShell7 = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue

    if ($null -eq $PowerShell7) {
        Write-Host 'PowerShell 7 is required but could not be found.' -ForegroundColor Red
        Write-Host 'Install it with: winget install --id Microsoft.PowerShell --source winget' -ForegroundColor Yellow
        Read-Host 'Press Enter to close'
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        Write-Host 'Save the script as a .ps1 file and start it again.' -ForegroundColor Red
        Read-Host 'Press Enter to close'
        exit 1
    }

    try {
        $process = Start-Process -FilePath $PowerShell7.Source `
            -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") `
            -Wait -PassThru -ErrorAction Stop
        exit $process.ExitCode
    }
    catch {
        Write-Host "PowerShell 7 could not be started: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host 'Press Enter to close'
        exit 1
    }
}

Clear-Host
Write-Host ''
Write-Host 'Empty Folder Cleanup (automatic)' -ForegroundColor Cyan
Write-Host '---------------------------------' -ForegroundColor DarkGray
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host ''

# Request and validate the root path.
do {
    $RootPath = (Read-Host 'Enter root path to scan').Trim().Trim('"')

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        Write-Host 'No path was entered. Please try again.' -ForegroundColor Yellow
        $ValidPath = $false
        continue
    }

    try {
        $ValidPath = Test-Path -LiteralPath $RootPath -PathType Container -ErrorAction Stop
        if (-not $ValidPath) {
            Write-Host "Path does not exist or cannot be accessed: $RootPath" -ForegroundColor Red
        }
    }
    catch {
        $ValidPath = $false
        Write-Host "Error accessing path: $($_.Exception.Message)" -ForegroundColor Red
    }
} until ($ValidPath)

Write-Host "`nSelected root path: $RootPath" -ForegroundColor Cyan
if ((Read-Host 'Start scan? (Y/N)') -notmatch '^[Yy]$') {
    Write-Host 'Scan cancelled.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 0
}

Write-Host "`nEnumerating folders..." -ForegroundColor Cyan
$EnumerationErrors = [System.Collections.Generic.List[object]]::new()
$ChildItemErrors = @()
try {
    $Folders = @(Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force `
        -ErrorAction SilentlyContinue -ErrorVariable ChildItemErrors)
}
catch {
    Write-Host "The root path could not be scanned: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

foreach ($errorRecord in $ChildItemErrors) {
    $EnumerationErrors.Add([PSCustomObject]@{
        Path = [string]$errorRecord.TargetObject
        Reason = $errorRecord.Exception.Message
    })
}

# Process deepest folders first. The root folder itself is not a deletion candidate.
$Folders = @($Folders | Sort-Object `
    @{ Expression = { $_.FullName.Length }; Descending = $true },
    @{ Expression = { $_.FullName }; Descending = $true })

$EmptyFolders = [System.Collections.Generic.List[object]]::new()
$ReadErrors = [System.Collections.Generic.List[object]]::new()
$CheckedFolderCount = 0
$TotalFolderCount = $Folders.Count

foreach ($Folder in $Folders) {
    $CheckedFolderCount++
    if ($TotalFolderCount -gt 0) {
        $percent = [int](100 * $CheckedFolderCount / $TotalFolderCount)
        Write-Progress -Activity 'Checking folders for content' `
            -Status "$CheckedFolderCount of $TotalFolderCount folders checked" `
            -PercentComplete $percent
    }

    try {
        $firstItem = Get-ChildItem -LiteralPath $Folder.FullName -Force -ErrorAction Stop |
            Select-Object -First 1
        if ($null -eq $firstItem) {
            $EmptyFolders.Add($Folder)
        }
    }
    catch {
        $ReadErrors.Add([PSCustomObject]@{
            Path = $Folder.FullName
            Reason = $_.Exception.Message
        })
    }
}
Write-Progress -Activity 'Checking folders for content' -Completed

$EmptyFolderCount = $EmptyFolders.Count
$TotalErrorCount = $EnumerationErrors.Count + $ReadErrors.Count
Write-Host "`nScan completed." -ForegroundColor Cyan
Write-Host "Folders enumerated : $TotalFolderCount"
Write-Host "Empty folders found: $EmptyFolderCount" -ForegroundColor Yellow
Write-Host "Scan/read errors   : $TotalErrorCount" -ForegroundColor $(if ($TotalErrorCount) { 'Red' } else { 'Green' })
if ($TotalErrorCount -gt 0) {
    Write-Host 'Folders that could not be read are not treated as empty.' -ForegroundColor Yellow
}

# Create the CSV log before any deletion, so a log creation failure prevents deletion.
$LogDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = $env:TEMP }
$LogFileName = 'EmptyFolderCleanup_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$LogPath = Join-Path -Path $LogDirectory -ChildPath $LogFileName
try {
    Set-Content -LiteralPath $LogPath -Value '"Timestamp","Path"' -Encoding utf8 -ErrorAction Stop
}
catch {
    Write-Host "Could not create the deletion log; no folders will be deleted. $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

if ($EmptyFolderCount -eq 0) {
    Write-Host 'No empty folders were found.' -ForegroundColor Green
    Write-Host "Log file: $LogPath" -ForegroundColor DarkGray
    Read-Host 'Press Enter to close'
    exit 0
}

Write-Host "`nFound $EmptyFolderCount empty folder(s). They will be rechecked before deletion." -ForegroundColor Yellow
Write-Host "Successful deletions will be logged to: $LogPath" -ForegroundColor Cyan
if ((Read-Host 'Delete all folders found empty? (Y/N)') -notmatch '^[Yy]$') {
    Write-Host 'Deletion cancelled. No folders were deleted.' -ForegroundColor Yellow
    Write-Host "Log file: $LogPath" -ForegroundColor DarkGray
    Read-Host 'Press Enter to close'
    exit 0
}

$DeletedCount = 0
$ChangedCount = 0
$DeleteErrorCount = 0
$LogErrorCount = 0

foreach ($Folder in $EmptyFolders) {
    $FolderPath = $Folder.FullName
    try {
        $FolderExists = Test-Path -LiteralPath $FolderPath -PathType Container -ErrorAction Stop
        if (-not $FolderExists) {
            $ChangedCount++
            Write-Host "Folder no longer exists; skipped: $FolderPath" -ForegroundColor DarkYellow
            continue
        }

        $CurrentContent = Get-ChildItem -LiteralPath $FolderPath -Force -ErrorAction Stop |
            Select-Object -First 1
        if ($null -ne $CurrentContent) {
            $ChangedCount++
            Write-Host "Folder is no longer empty; skipped: $FolderPath" -ForegroundColor DarkYellow
            continue
        }

        # No -Recurse: only an empty folder is removed.
        Remove-Item -LiteralPath $FolderPath -Force -ErrorAction Stop
        $DeletedCount++
        Write-Host "Deleted: $FolderPath" -ForegroundColor Green

        try {
            [PSCustomObject]@{
                Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Path = $FolderPath
            } | Export-Csv -LiteralPath $LogPath -NoTypeInformation -Append -Encoding utf8 -ErrorAction Stop
        }
        catch {
            $LogErrorCount++
            Write-Host "Folder was deleted but could not be logged: $FolderPath" -ForegroundColor Red
            Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    }
    catch {
        $DeleteErrorCount++
        Write-Host "Error processing folder: $FolderPath" -ForegroundColor Red
        Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

Write-Host "`nFinished." -ForegroundColor Green
Write-Host "Empty folders found : $EmptyFolderCount"
Write-Host "Deleted             : $DeletedCount" -ForegroundColor Green
Write-Host "Changed or missing  : $ChangedCount" -ForegroundColor Yellow
Write-Host "Deletion errors     : $DeleteErrorCount" -ForegroundColor $(if ($DeleteErrorCount) { 'Red' } else { 'Green' })
Write-Host "Log write errors    : $LogErrorCount" -ForegroundColor $(if ($LogErrorCount) { 'Red' } else { 'Green' })
Write-Host "Scan/read errors    : $TotalErrorCount" -ForegroundColor $(if ($TotalErrorCount) { 'Red' } else { 'Green' })
Write-Host "Log file            : $LogPath"
Write-Host ''
Read-Host 'Press Enter to close'
