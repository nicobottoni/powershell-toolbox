<#
.SYNOPSIS
Finds empty folders within a directory structure and optionally removes them.

.DESCRIPTION
Recursively scans a specified path, including long paths and UNC shares,
for empty folders. Each empty folder can be reviewed and deleted individually.

.NOTES
Author: Nico Bottoni
Repository: powershell-toolbox
Category: Filesystem
Created: 2024-XX-XX
Last Updated: 2025-11-11
#>

# Root path to scan
# Examples:
# "D:\Data\Folder"
# "\\FILESERVER\Share\Folder"
$RootPath = ""

function Convert-ToLongPath {
    param (
        [string]$Path
    )

    if ($Path.StartsWith("\\?\")) {
        return $Path
    }

    if ($Path.StartsWith("\\")) {
        return "\\?\UNC\" + $Path.TrimStart("\")
    }

    return "\\?\" + $Path
}

Write-Host "Starting empty folder scan..." -ForegroundColor Cyan
Write-Host "RootPath: $RootPath"
Write-Host ""

$LongRootPath = Convert-ToLongPath -Path $RootPath

$EmptyFolders = Get-ChildItem `
    -LiteralPath $LongRootPath `
    -Directory `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Where-Object {

        $FolderPath = $_.FullName

        try {
            $Content = Get-ChildItem `
                -LiteralPath $FolderPath `
                -Force `
                -ErrorAction Stop

            if ($Content.Count -eq 0) {
                return $true
            }
            else {
                return $false
            }
        }
        catch {
            Write-Host "Fehler beim Lesen: $FolderPath" -ForegroundColor Red
            Write-Host "Grund: $($_.Exception.Message)" -ForegroundColor DarkRed
            return $false
        }
    }

Write-Host ""
Write-Host "Scan completed." -ForegroundColor Cyan
Write-Host "Empty folders found: $($EmptyFolders.Count)" -ForegroundColor Yellow
Write-Host ""

foreach ($Folder in $EmptyFolders) {

    $FolderPath = $Folder.FullName

    Write-Host ""
    Write-Host "Empty folders found:" -ForegroundColor Yellow
    Write-Host $FolderPath

    $Choice = Read-Host "Delete folder? (Y/N)"

    if ($Choice -match '^[Yy]$') {

        try {
            $LongFolderPath = Convert-ToLongPath -Path $FolderPath

            Remove-Item -LiteralPath $LongFolderPath -Force -ErrorAction Stop

            Write-Host "Deleted." -ForegroundColor Green
        }
        catch {
            Write-Host "Error deleting folder: $FolderPath" -ForegroundColor Red
            Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor DarkRed
        }

    }
    else {
        Write-Host "Skipped." -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "Finished." -ForegroundColor Green