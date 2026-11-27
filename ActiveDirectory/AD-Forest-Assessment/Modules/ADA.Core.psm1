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

    New-Item `
        -Path $outputPath `
        -ItemType Directory `
        -Force `
        -ErrorAction Stop |
    Out-Null

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

    Add-Content `
        -Path $LogPath `
        -Value $logEntry `
        -Encoding UTF8 `
        -ErrorAction Stop
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
        -Encoding UTF8 `
        -ErrorAction Stop

    return $csvPath
}

function Test-AssessmentConfiguration {

    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $requiredSettings = @(
        'InactiveUserDays'
        'InactiveComputerDays'
        'NewComputerGraceDays'
    )

    foreach ($setting in $requiredSettings) {

        if (-not $Config.ContainsKey($setting)) {
            throw "Required configuration setting is missing: $setting"
        }
    }

    if ($Config.InactiveUserDays -isnot [int]) {
        throw "InactiveUserDays must be an integer."
    }

    if ($Config.InactiveUserDays -lt 1 -or
        $Config.InactiveUserDays -gt 365) {

        throw "InactiveUserDays must be between 1 and 365."
    }


    if ($Config.InactiveComputerDays -isnot [int]) {
        throw "InactiveComputerDays must be an integer."
    }

    if ($Config.InactiveComputerDays -lt 1 -or
        $Config.InactiveComputerDays -gt 365) {

        throw "InactiveComputerDays must be between 1 and 365."
    }


    if ($Config.NewComputerGraceDays -isnot [int]) {
        throw "NewComputerGraceDays must be an integer."
    }

    if ($Config.NewComputerGraceDays -lt 0 -or
        $Config.NewComputerGraceDays -gt 365) {

        throw "NewComputerGraceDays must be between 0 and 365."
    }

    return $true
}


Export-ModuleMember -Function @(
    'Test-AssessmentPrerequisite'
    'Test-AssessmentConfiguration'
    'New-AssessmentOutputDirectory'
    'Write-AssessmentLog'
    'Export-AssessmentData'
)