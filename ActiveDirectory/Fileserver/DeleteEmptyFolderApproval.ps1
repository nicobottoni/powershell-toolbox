# Root-Pfad anpassen
# "D:\Data\....."
# "\\KONZFS1861.wgs.wuerth.com\KONZFS1861_vol1\...."
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

Write-Host "Starte Suche nach leeren Ordnern..." -ForegroundColor Cyan
Write-Host "RootPath: $RootPath"
Write-Host ""

$LongRootPath = Convert-ToLongPath -Path $RootPath

$EmptyFolders = Get-ChildItem -LiteralPath $LongRootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Where-Object {

        $FolderPath = $_.FullName

        try {
            $Content = Get-ChildItem -LiteralPath $FolderPath -Force -ErrorAction Stop

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
Write-Host "Suche abgeschlossen." -ForegroundColor Cyan
Write-Host "Gefundene leere Ordner: $($EmptyFolders.Count)" -ForegroundColor Yellow
Write-Host ""

foreach ($Folder in $EmptyFolders) {

    $FolderPath = $Folder.FullName

    Write-Host ""
    Write-Host "Leerer Ordner gefunden:" -ForegroundColor Yellow
    Write-Host $FolderPath

    $Choice = Read-Host "Ordner löschen? (J/N)"

    if ($Choice -match '^[JjYy]$') {

        try {
            $LongFolderPath = Convert-ToLongPath -Path $FolderPath

            Remove-Item -LiteralPath $LongFolderPath -Force -ErrorAction Stop

            Write-Host "Gelöscht." -ForegroundColor Green
        }
        catch {
            Write-Host "Fehler beim Löschen: $FolderPath" -ForegroundColor Red
            Write-Host "Grund: $($_.Exception.Message)" -ForegroundColor DarkRed
        }

    }
    else {
        Write-Host "Übersprungen." -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "Fertig." -ForegroundColor Green