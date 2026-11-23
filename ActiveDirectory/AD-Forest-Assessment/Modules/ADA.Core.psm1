function Test-AssessmentPrerequisite {

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "The ActiveDirectory PowerShell module is not available."
    }
}

function New-AssessmentOutputDirectory {

    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputPath = Join-Path $BasePath "AD-Assessment-$timestamp"

    New-Item -Path $outputPath -ItemType Directory -Force | Out-Null

    return $outputPath
}

function Write-AssessmentLog {

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$LogPath,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $logEntry = "$timestamp [$Level] $Message"

    Add-Content -Path $LogPath -Value $logEntry
}

function Export-AssessmentData {

    param(
        [Parameter(Mandatory)]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $csvPath = Join-Path $OutputPath "$Name.csv"

    $Data | Export-Csv `
        -Path $csvPath `
        -NoTypeInformation `
        -Encoding UTF8

    return $csvPath
}

Export-ModuleMember -Function @(
    'Test-AssessmentPrerequisite'
    'New-AssessmentOutputDirectory'
    'Write-AssessmentLog'
    'Export-AssessmentData'
)

