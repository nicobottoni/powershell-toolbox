<#
.SYNOPSIS
Finds empty folders within a directory structure and optionally removes them.

.DESCRIPTION
Recursively scans a user-specified local path or UNC share for empty folders.

If the script is started with Windows PowerShell 5.1, it automatically
restarts itself in a separate PowerShell 7 window.

Long directory paths are supported through PowerShell 7.

Each empty folder can be reviewed individually. Immediately before deletion,
the folder is checked again to verify that it still exists and remains empty.

.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: Filesystem
Created: 2024-12-11
Last Updated: 2026-11-10

.REQUIREMENTS
PowerShell 7 or newer
#>


# ------------------------------------------------------------
# Relaunch with PowerShell 7
# ------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 7) {

    $PowerShell7 = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue

    if ($null -eq $PowerShell7) {

        Write-Host ""
        Write-Host "PowerShell 7 is required but could not be found." `
            -ForegroundColor Red

        Write-Host ""
        Write-Host "Install PowerShell 7 with the following command:" `
            -ForegroundColor Yellow

        Write-Host ""
        Write-Host "winget install --id Microsoft.PowerShell --source winget"
        Write-Host ""

        Read-Host "Press Enter to close"
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {

        Write-Host ""
        Write-Host "The current script path could not be determined." `
            -ForegroundColor Red

        Write-Host "Save the script as a .ps1 file and start it again." `
            -ForegroundColor Yellow

        Write-Host ""

        Read-Host "Press Enter to close"
        exit 1
    }

    Write-Host ""
    Write-Host "Restarting script with PowerShell 7..." `
        -ForegroundColor Cyan

    Write-Host ""

    $PowerShell7Arguments = @(
        "-NoLogo"
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$PSCommandPath`""
    )

    try {

        $PowerShell7Process = Start-Process `
            -FilePath $PowerShell7.Source `
            -ArgumentList $PowerShell7Arguments `
            -Wait `
            -PassThru `
            -ErrorAction Stop

        exit $PowerShell7Process.ExitCode
    }
    catch {

        Write-Host ""
        Write-Host "PowerShell 7 could not be started." `
            -ForegroundColor Red

        Write-Host "Reason: $($_.Exception.Message)" `
            -ForegroundColor DarkRed

        Write-Host ""

        Read-Host "Press Enter to close"
        exit 1
    }
}


# ------------------------------------------------------------
# Verify PowerShell version
# ------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 7) {

    Write-Host ""
    Write-Host "This script requires PowerShell 7 or newer." `
        -ForegroundColor Red

    Write-Host ""

    Read-Host "Press Enter to close"
    exit 1
}


# ------------------------------------------------------------
# Display script information
# ------------------------------------------------------------

Clear-Host

Write-Host ""
Write-Host "Empty Folder Cleanup" -ForegroundColor Cyan
Write-Host "--------------------" -ForegroundColor DarkGray
Write-Host ""

Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" `
    -ForegroundColor DarkGray

Write-Host "PowerShell Edition: $($PSVersionTable.PSEdition)" `
    -ForegroundColor DarkGray

Write-Host ""


# ------------------------------------------------------------
# Request root path
# ------------------------------------------------------------

$RootPath = $null
$ValidPath = $false

do {

    $RootPath = Read-Host "Enter root path to scan"

    if ($null -ne $RootPath) {

        # Remove spaces and quotation marks accidentally
        # included when copying the path.

        $RootPath = $RootPath.Trim()
        $RootPath = $RootPath.Trim('"')
    }

    if ([string]::IsNullOrWhiteSpace($RootPath)) {

        Write-Host ""
        Write-Host "No path was entered. Please try again." `
            -ForegroundColor Yellow

        Write-Host ""

        $ValidPath = $false
        continue
    }

    try {

        $ValidPath = Test-Path `
            -LiteralPath $RootPath `
            -PathType Container `
            -ErrorAction Stop

        if (-not $ValidPath) {

            Write-Host ""
            Write-Host "The path does not exist or cannot be accessed:" `
                -ForegroundColor Red

            Write-Host $RootPath
            Write-Host ""
        }
    }
    catch {

        $ValidPath = $false

        Write-Host ""
        Write-Host "Error accessing the path:" `
            -ForegroundColor Red

        Write-Host $RootPath

        Write-Host "Reason: $($_.Exception.Message)" `
            -ForegroundColor DarkRed

        Write-Host ""
    }

} until ($ValidPath)


# ------------------------------------------------------------
# Confirm scan
# ------------------------------------------------------------

Write-Host ""
Write-Host "Selected root path:" -ForegroundColor Cyan
Write-Host $RootPath
Write-Host ""

$StartScan = Read-Host "Start scan? (Y/N)"

if ($StartScan -notmatch '^[Yy]$') {

    Write-Host ""
    Write-Host "Scan cancelled." -ForegroundColor Yellow
    Write-Host ""

    Read-Host "Press Enter to close"
    exit 0
}


# ------------------------------------------------------------
# Enumerate folders
# ------------------------------------------------------------

Write-Host ""
Write-Host "Enumerating folders..." -ForegroundColor Cyan
Write-Host "This may take some time on large directory structures."
Write-Host ""


$EnumerationErrors = [System.Collections.Generic.List[object]]::new()
$ChildItemErrors = @()


try {

    $Folders = @(
        Get-ChildItem `
            -LiteralPath $RootPath `
            -Directory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue `
            -ErrorVariable ChildItemErrors
    )
}
catch {

    Write-Host ""
    Write-Host "The root path could not be scanned." `
        -ForegroundColor Red

    Write-Host "Reason: $($_.Exception.Message)" `
        -ForegroundColor DarkRed

    Write-Host ""

    Read-Host "Press Enter to close"
    exit 1
}


foreach ($EnumerationError in $ChildItemErrors) {

    $EnumerationErrors.Add(
        [PSCustomObject]@{
            Path   = [string]$EnumerationError.TargetObject
            Reason = $EnumerationError.Exception.Message
        }
    )
}


# ------------------------------------------------t deepest folders first
# ------------------------------------------------------------

$Folders = @(
    $Folders |
        Sort-Object `
            @{ Expression = { $_.FullName.Length }; Descending = $true },
            @{ Expression = { $_.FullName }; Descending = $true }
)


# ------------------------------------------------------------
# Find empty folders
# ------------------------------------------------------------

$EmptyFolders = [System.Collections.Generic.List[object]]::new()
$ReadErrors = [System.Collections.Generic.List[object]]::new()

$TotalFolderCount = $Folders.Count
$CheckedFolderCount = 0


foreach ($Folder in $Folders) {

    $CheckedFolderCount++

    if ($TotalFolderCount -gt 0) {

    $ProgressPercent = [int](
        ([double]$CheckedFolderCount / [double]$TotalFolderCount) * 100
    )

    # Ensure value stays between 0 and 100
    $ProgressPercent = [Math]::Min(
        100,
        [Math]::Max(0, $ProgressPercent)
    )

    Write-Progress `
        -Activity "Checking folders for content" `
        -Status "$CheckedFolderCount of $TotalFolderCount folders checked" `
        -PercentComplete $ProgressPercent
}

    $FolderPath = $Folder.FullName

    try {

        $FirstItem = Get-ChildItem `
            -LiteralPath $FolderPath `
            -Force `
            -ErrorAction Stop |
            Select-Object -First 1

        if ($null -eq $FirstItem) {
            $EmptyFolders.Add($Folder)
        }
    }
    catch {

        $ReadErrors.Add(
            [PSCustomObject]@{
                Path   = $FolderPath
                Reason = $_.Exception.Message
            }
        )
    }
}


Write-Progress `
    -Activity "Checking folders for content" `
    -Completed


# ------------------------------------------------------------
# Display scan results
# ------------------------------------------------------------

$EmptyFolderCount = $EmptyFolders.Count
$EnumerationErrorCount = $EnumerationErrors.Count
$ReadErrorCount = $ReadErrors.Count
$TotalErrorCount = $EnumerationErrorCount + $ReadErrorCount


Write-Host ""
Write-Host "Scan completed." -ForegroundColor Cyan
Write-Host ""

Write-Host "Folders enumerated : $TotalFolderCount"

Write-Host "Empty folders found: $EmptyFolderCount" `
    -ForegroundColor Yellow

Write-Host "Scan/read errors   : $TotalErrorCount" `
    -ForegroundColor $(if ($TotalErrorCount -gt 0) {
        "Red"
    }
    else {
        "Green"
    })

Write-Host ""


if ($TotalErrorCount -gt 0) {

    Write-Host "Folders that could not be read are not treated as empty." `
        -ForegroundColor Yellow

    Write-Host "Those folders will not be offered for deletion." `
        -ForegroundColor Yellow

    Write-Host ""
}


if ($EmptyFolderCount -eq 0) {

    Write-Host "No empty folders were found." `
        -ForegroundColor Green

    Write-Host ""

    Read-Host "Press Enter to close"
    exit 0
}


# ------------------------------------------------------------
# Review empty folders
# ------------------------------------------------------------

$DeletedCount = 0
$SkippedCount = 0
$ChangedCount = 0
$DeleteErrorCount = 0
$ReviewCancelled = $false


foreach ($Folder in $EmptyFolders) {

    $FolderPath = $Folder.FullName

    Write-Host ""
    Write-Host "Empty folder found:" -ForegroundColor Yellow
    Write-Host $FolderPath
    Write-Host ""

    do {

        $Choice = Read-Host "Delete folder? (Y/N/Q)"

        if ($Choice -notmatch '^[YyNnQq]$') {

            Write-Host "Please enter Y, N, or Q." `
                -ForegroundColor Yellow
        }

    } until ($Choice -match '^[YyNnQq]$')


    if ($Choice -match '^[Qq]$') {

        $ReviewCancelled = $true

        Write-Host ""
        Write-Host "Review cancelled by user." `
            -ForegroundColor Yellow

        break
    }


    if ($Choice -match '^[Nn]$') {

        $SkippedCount++

        Write-Host "Skipped." -ForegroundColor Cyan

        continue
    }


    try {

        # Verify that the folder still exists.

        $FolderExists = Test-Path `
            -LiteralPath $FolderPath `
            -PathType Container `
            -ErrorAction Stop

        if (-not $FolderExists) {

            $ChangedCount++

            Write-Host "Folder no longer exists. Skipped." `
                -ForegroundColor DarkYellow

            continue
        }


        # Verify that the folder is still empty.

        $CurrentContent = Get-ChildItem `
            -LiteralPath $FolderPath `
            -Force `
            -ErrorAction Stop |
            Select-Object -First 1

        if ($null -ne $CurrentContent) {

            $ChangedCount++

            Write-Host "Folder is no longer empty. Skipped." `
                -ForegroundColor DarkYellow

            continue
        }


        # Remove only the empty folder.
        # -Recurse is intentionally not used.

        Remove-Item `
            -LiteralPath $FolderPath `
            -Force `
            -ErrorAction Stop

        $DeletedCount++

        Write-Host "Deleted." -ForegroundColor Green
    }
    catch {

        $DeleteErrorCount++

        Write-Host "Error deleting folder:" `
            -ForegroundColor Red

        Write-Host $FolderPath

        Write-Host "Reason: $($_.Exception.Message)" `
            -ForegroundColor DarkRed
    }
}


# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------

Write-Host ""
Write-Host "Finished." -ForegroundColor Green
Write-Host ""

Write-Host "Empty folders found : $EmptyFolderCount"

Write-Host "Deleted             : $DeletedCount" `
    -ForegroundColor Green

Write-Host "Skipped             : $SkippedCount" `
    -ForegroundColor Cyan

Write-Host "Changed or missing  : $ChangedCount" `
    -ForegroundColor Yellow

Write-Host "Deletion errors     : $DeleteErrorCount" `
    -ForegroundColor $(if ($DeleteErrorCount -gt 0) {
        "Red"
    }
    else {
        "Green"
    })

Write-Host "Scan/read errors    : $TotalErrorCount" `
    -ForegroundColor $(if ($TotalErrorCount -gt 0) {
        "Red"
    }
    else {
        "Green"
    })


if ($ReviewCancelled) {

    Write-Host ""
    Write-Host "The folder review was cancelled before all results were processed." `
        -ForegroundColor Yellow
}


Write-Host ""
Read-Host "Press Enter to close"