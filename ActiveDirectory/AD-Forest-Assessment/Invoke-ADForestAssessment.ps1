# Assessment metadata
$assessmentVersion = "1.0.0"
$assessmentStartTime = Get-Date

# Import required modules
Import-Module "$PSScriptRoot\Modules\ADA.Core.psm1" -Force

try {

    Test-AssessmentPrerequisite

}
catch {

    Write-Host ""
    Write-Host "Assessment failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    return
}

Import-Module ActiveDirectory
Import-Module "$PSScriptRoot\Modules\ADA.Forest.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.Domain.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.DomainController.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.User.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.Computer.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.Trust.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.Group.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.Security.psm1" -Force
Import-Module "$PSScriptRoot\Modules\ADA.Reporting.psm1" -Force

# Load assessment configuration
$configPath = Join-Path $PSScriptRoot "Config\AssessmentConfig.psd1"

try {

    if (-not (Test-Path $configPath)) {
        throw "Assessment configuration file not found: $configPath"
    }

    $config = Import-PowerShellDataFile `
        -Path $configPath `
        -ErrorAction Stop

    Test-AssessmentConfiguration `
        -Config $config | Out-Null

}
catch {

    Write-Host ""
    Write-Host "Assessment failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    return
}

$config = Import-PowerShellDataFile -Path $configPath

# Create output directory
$outputPath = New-AssessmentOutputDirectory `
    -BasePath "$PSScriptRoot\Output"

$logPath = Join-Path $outputPath "Assessment.log"

# Initialize assessment status
$assessmentStatus = "Completed"
$assessmentWarnings = @()

Write-AssessmentLog `
    -Message "AD Forest Assessment started." `
    -LogPath $logPath


# Forest assessment
Write-AssessmentLog `
    -Message "Collecting forest information." `
    -LogPath $logPath

try {

    $forest = Get-AssessmentForest

}
catch {

    $assessmentStatus = "Failed"

    $errorMessage = "Failed to collect forest information: $($_.Exception.Message)"

    Write-AssessmentLog `
        -Message $errorMessage `
        -LogPath $logPath `
        -Level "ERROR"

    Write-Host ""
    Write-Host "Assessment failed." -ForegroundColor Red
    Write-Host $errorMessage -ForegroundColor Red
    Write-Host "Output directory: $outputPath"

    return
}

Write-Host ""
Write-Host "Forest Information" -ForegroundColor Cyan
Write-Host "=================="
$forest | Format-List


# Export Forest information
Export-AssessmentData `
    -Data $forest `
    -Name "Forest" `
    -OutputPath $outputPath | Out-Null

# Check group assessment warnings
$groupQueryErrors = @(
    $groups |
        Where-Object { -not $_.MembershipQuerySuccessful }
)

if ($groupQueryErrors.Count -gt 0) {

    $assessmentStatus = "CompletedWithWarnings"

    $warningMessage = "$($groupQueryErrors.Count) group membership query(s) could not be completed."

    $assessmentWarnings += $warningMessage

    Write-AssessmentLog `
        -Message $warningMessage `
        -LogPath $logPath `
        -Level "WARNING"
}

Write-AssessmentLog `
    -Message "Forest information exported to Forest.csv." `
    -LogPath $logPath


# Domain assessment
Write-AssessmentLog `
    -Message "Collecting domain information." `
    -LogPath $logPath

$domains = Get-AssessmentDomain

Write-Host ""
Write-Host "Domain Information" -ForegroundColor Cyan
Write-Host "=================="
$domains | Format-List


# Export Domains information
Export-AssessmentData `
    -Data $domains `
    -Name "Domains" `
    -OutputPath $outputPath | Out-Null

Write-AssessmentLog `
    -Message "Domain information exported to Domains.csv." `
    -LogPath $logPath


# Domain Controller assessment
Write-AssessmentLog `
    -Message "Collecting domain controller information." `
    -LogPath $logPath

$domainControllers = Get-AssessmentDomainController

Write-Host ""
Write-Host "Domain Controller Information" -ForegroundColor Cyan
Write-Host "============================="
$domainControllers | Format-List


# Export Domain Controller information
Export-AssessmentData `
    -Data $domainControllers `
    -Name "DomainControllers" `
    -OutputPath $outputPath | Out-Null

Write-AssessmentLog `
    -Message "Domain controller information exported to DomainControllers.csv." `
    -LogPath $logPath


# User assessment
Write-AssessmentLog `
    -Message "Collecting user information." `
    -LogPath $logPath

$users = Get-AssessmentUser `
    -InactiveDays $config.InactiveUserDays

Write-Host ""
Write-Host "User Information" -ForegroundColor Cyan
Write-Host "================"
$users | Format-Table `
    SamAccountName,
    Enabled,
    LastLogonDate,
    PasswordNeverExpires,
    NeverLoggedOn,
    IsInactive `
    -AutoSize

Write-Host ""
Write-Host "User Summary" -ForegroundColor Cyan
Write-Host "============"

Write-Host "Total Users             :" @($users).Count
Write-Host "Enabled Users           :" @($users | Where-Object Enabled).Count
Write-Host "Disabled Users          :" @($users | Where-Object { -not $_.Enabled }).Count
Write-Host "Never Logged On         :" @($users | Where-Object NeverLoggedOn).Count
Write-Host "Inactive > $($config.InactiveUserDays) Days :" `
    @($users | Where-Object IsInactive).Count
Write-Host "Password Never Expires  :" @($users | Where-Object PasswordNeverExpires).Count
Write-Host "Password Not Required   :" @($users | Where-Object PasswordNotRequired).Count
Write-Host "Locked Users            :" @($users | Where-Object LockedOut).Count


# Export user information
Export-AssessmentData `
    -Data $users `
    -Name "Users" `
    -OutputPath $outputPath | Out-Null

Write-AssessmentLog `
    -Message "User information exported to Users.csv." `
    -LogPath $logPath


# Computer assessment
Write-AssessmentLog `
    -Message "Collecting computer information." `
    -LogPath $logPath

$computers = Get-AssessmentComputer `
    -InactiveDays $config.InactiveComputerDays

Write-Host ""
Write-Host "Computer Information" -ForegroundColor Cyan
Write-Host "===================="
$computers | Format-Table `
    ComputerName,
    Enabled,
    OperatingSystem,
    LastLogonDate,
    NeverLoggedOn,
    IsInactive `
    -AutoSize


Write-Host ""
Write-Host "Computer Summary" -ForegroundColor Cyan
Write-Host "================"

Write-Host "Total Computers         :" @($computers).Count
Write-Host "Enabled Computers       :" @($computers | Where-Object Enabled).Count
Write-Host "Disabled Computers      :" @($computers | Where-Object { -not $_.Enabled }).Count
Write-Host "Never Logged On         :" @($computers | Where-Object NeverLoggedOn).Count
Write-Host "Inactive > $($config.InactiveComputerDays) Days :" `
    @($computers | Where-Object IsInactive).Count


# Export computer information
Export-AssessmentData `
    -Data $computers `
    -Name "Computers" `
    -OutputPath $outputPath | Out-Null

Write-AssessmentLog `
    -Message "Computer information exported to Computers.csv." `
    -LogPath $logPath


# Group assessment
Write-AssessmentLog `
    -Message "Collecting group information." `
    -LogPath $logPath

$groups = Get-AssessmentGroup

Write-Host ""
Write-Host "Group Information" -ForegroundColor Cyan
Write-Host "================="
$groups | Format-Table `
    GroupName,
    GroupCategory,
    GroupScope,
    MemberCount,
    NestedGroupCount,
    IsEmpty `
    -AutoSize


Write-Host ""
Write-Host "Group Summary" -ForegroundColor Cyan
Write-Host "============="

Write-Host "Total Groups            :" @($groups).Count
Write-Host "Security Groups         :" @($groups | Where-Object GroupCategory -eq "Security").Count
Write-Host "Distribution Groups     :" @($groups | Where-Object GroupCategory -eq "Distribution").Count
Write-Host "Global Groups           :" @($groups | Where-Object GroupScope -eq "Global").Count
Write-Host "Universal Groups        :" @($groups | Where-Object GroupScope -eq "Universal").Count
Write-Host "Domain Local Groups     :" @($groups | Where-Object GroupScope -eq "DomainLocal").Count
Write-Host "Empty Groups            :" @($groups | Where-Object IsEmpty).Count
Write-Host "Without Description     :" @($groups | Where-Object { -not $_.HasDescription }).Count
Write-Host "Groups with Nesting     :" @($groups | Where-Object { $_.NestedGroupCount -gt 0 }).Count


# Export group information
Export-AssessmentData `
    -Data $groups `
    -Name "Groups" `
    -OutputPath $outputPath | Out-Null

Write-AssessmentLog `
    -Message "Group information exported to Groups.csv." `
    -LogPath $logPath


# Privileged account assessment
Write-AssessmentLog `
    -Message "Collecting privileged account information." `
    -LogPath $logPath

$privilegedAccounts = @(
    Get-AssessmentPrivilegedAccount
)

Write-Host ""
Write-Host "Privileged Account Information" -ForegroundColor Cyan
Write-Host "=============================="

$privilegedAccounts | Format-Table `
    PrivilegedGroup,
    MembershipType,
    SamAccountName,
    Enabled,
    LastLogonDate,
    PasswordNeverExpires `
    -AutoSize


# Get unique privileged accounts
$uniquePrivilegedAccounts = @(
    $privilegedAccounts |
        Select-Object Domain, SamAccountName -Unique
)

Write-Host ""
Write-Host "Privileged Account Summary" -ForegroundColor Cyan
Write-Host "=========================="

Write-Host "Privileged Memberships      :" @($privilegedAccounts).Count
Write-Host "Unique Privileged Accounts  :" @($uniquePrivilegedAccounts).Count
Write-Host "Direct Memberships          :" @($privilegedAccounts | Where-Object MembershipType -eq "Direct").Count
Write-Host "Indirect Memberships        :" @($privilegedAccounts | Where-Object MembershipType -eq "Indirect").Count
Write-Host "Enabled Memberships         :" @($privilegedAccounts | Where-Object Enabled).Count
Write-Host "Disabled Memberships        :" @($privilegedAccounts | Where-Object { -not $_.Enabled }).Count
Write-Host "Password Never Expires      :" @($privilegedAccounts | Where-Object PasswordNeverExpires).Count
Write-Host "Password Not Required       :" @($privilegedAccounts | Where-Object PasswordNotRequired).Count


# Export privileged account information
if (@($privilegedAccounts).Count -gt 0) {

    Export-AssessmentData `
        -Data $privilegedAccounts `
        -Name "PrivilegedAccounts" `
        -OutputPath $outputPath | Out-Null

    Write-AssessmentLog `
        -Message "Privileged account information exported to PrivilegedAccounts.csv." `
        -LogPath $logPath
}
else {

    Write-AssessmentLog `
        -Message "No privileged user accounts found." `
        -LogPath $logPath
}


# Security finding assessment
Write-AssessmentLog `
    -Message "Analyzing privileged account security findings." `
    -LogPath $logPath

$findings = @()

if (@($privilegedAccounts).Count -gt 0) {

    $findings += @(
        Test-AssessmentPrivilegedAccount `
            -PrivilegedAccounts $privilegedAccounts `
            -InactiveDays $config.InactiveUserDays
    )
}

$findings += @(
    Test-AssessmentUserSecurity `
        -Users $users `
        -PrivilegedAccounts $privilegedAccounts
)

$findings += @(
    Test-AssessmentComputerSecurity `
        -Computers $computers `
        -InactiveDays $config.InactiveComputerDays `
        -NewComputerGraceDays $config.NewComputerGraceDays
)

Write-Host ""
Write-Host "Security Findings" -ForegroundColor Cyan
Write-Host "================="

if (@($findings).Count -eq 0) {

    Write-Host "No security findings detected." -ForegroundColor Green

}
else {

    $findings |
        Sort-Object @{
            Expression = {
                switch ($_.Severity) {
                    'Critical' { 1 }
                    'High'     { 2 }
                    'Medium'   { 3 }
                    'Low'      { 4 }
                    default    { 5 }
                }
            }
        }, ObjectName |
        Format-Table `
            Severity,
            Category,
            ObjectName,
            Finding `
            -AutoSize `
            -Wrap
}

Write-Host ""
Write-Host "Security Finding Summary" -ForegroundColor Cyan
Write-Host "========================"

Write-Host "Total Findings          :" @($findings).Count
Write-Host "Critical Findings       :" @($findings | Where-Object Severity -eq "Critical").Count
Write-Host "High Findings           :" @($findings | Where-Object Severity -eq "High").Count
Write-Host "Medium Findings         :" @($findings | Where-Object Severity -eq "Medium").Count
Write-Host "Low Findings            :" @($findings | Where-Object Severity -eq "Low").Count


# Export security findings
if (@($findings).Count -gt 0) {

    Export-AssessmentData `
        -Data $findings `
        -Name "Findings" `
        -OutputPath $outputPath | Out-Null

    Write-AssessmentLog `
        -Message "Security findings exported to Findings.csv." `
        -LogPath $logPath
}
else {

    Write-AssessmentLog `
        -Message "No security findings detected." `
        -LogPath $logPath
}


# Trust assessment
Write-AssessmentLog `
    -Message "Collecting trust information." `
    -LogPath $logPath

$trusts = Get-AssessmentTrust

Write-Host ""
Write-Host "Trust Information" -ForegroundColor Cyan
Write-Host "================="

if (@($trusts).Count -eq 0) {

    Write-Host "No trusts found." -ForegroundColor DarkGray

}
else {

    $trusts | Format-Table `
        Source,
        Target,
        Direction,
        TrustType,
        ForestTransitive,
        IntraForest `
        -AutoSize
}

Write-Host ""
Write-Host "Trust Summary" -ForegroundColor Cyan
Write-Host "============="

Write-Host "Total Trusts            :" @($trusts).Count
Write-Host "Bidirectional Trusts    :" @($trusts | Where-Object Direction -eq "Bidirectional").Count
Write-Host "Inbound Trusts          :" @($trusts | Where-Object Direction -eq "Inbound").Count
Write-Host "Outbound Trusts         :" @($trusts | Where-Object Direction -eq "Outbound").Count
Write-Host "Forest Trusts           :" @($trusts | Where-Object ForestTransitive).Count


# Export trust information
if (@($trusts).Count -gt 0) {

    Export-AssessmentData `
        -Data $trusts `
        -Name "Trusts" `
        -OutputPath $outputPath | Out-Null

    Write-AssessmentLog `
        -Message "Trust information exported to Trusts.csv." `
        -LogPath $logPath
}
else {

    Write-AssessmentLog `
        -Message "No trusts found." `
        -LogPath $logPath
}


# Finalize assessment metadata
$assessmentEndTime = Get-Date
$assessmentDuration = $assessmentEndTime - $assessmentStartTime

$assessmentMetadata = [PSCustomObject]@{
    Version           = $assessmentVersion
    HostName          = $env:COMPUTERNAME
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    StartTime         = $assessmentStartTime
    EndTime           = $assessmentEndTime
    Duration          = $assessmentDuration
}


# Generate HTML report
Write-AssessmentLog `
    -Message "Generating HTML assessment report." `
    -LogPath $logPath

$reportPath = New-AssessmentHtmlReport `
    -OutputPath $outputPath `
    -AssessmentStatus $assessmentStatus `
    -AssessmentWarnings $assessmentWarnings `
    -AssessmentMetadata $assessmentMetadata `
    -InactiveUserDays $config.InactiveUserDays `
    -InactiveComputerDays $config.InactiveComputerDays `
    -Forest $forest `
    -Domains $domains `
    -DomainControllers $domainControllers `
    -Users $users `
    -Computers $computers `
    -Groups $groups `
    -PrivilegedAccounts $privilegedAccounts `
    -Trusts $trusts `
    -Findings $findings

Write-AssessmentLog `
    -Message "HTML assessment report created: AD-Forest-Assessment.html." `
    -LogPath $logPath


# Complete assessment
if ($assessmentStatus -eq "Completed") {

    Write-AssessmentLog `
        -Message "AD Forest Assessment completed successfully." `
        -LogPath $logPath

}
elseif ($assessmentStatus -eq "CompletedWithWarnings") {

    Write-AssessmentLog `
        -Message "AD Forest Assessment completed with warnings." `
        -LogPath $logPath `
        -Level "WARNING"
}

Write-Host ""

if ($assessmentStatus -eq "Completed") {

    Write-Host "Assessment completed successfully." `
        -ForegroundColor Green

}
elseif ($assessmentStatus -eq "CompletedWithWarnings") {

    Write-Host "Assessment completed with warnings." `
        -ForegroundColor Yellow

    foreach ($warning in $assessmentWarnings) {
        Write-Host "  - $warning" -ForegroundColor Yellow
    }
}

Write-Host "Output directory: $outputPath"