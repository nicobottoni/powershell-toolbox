function New-AssessmentHtmlReport {

    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [object]$Forest,

        [Parameter(Mandatory)]
        [object[]]$Domains,

        [Parameter(Mandatory)]
        [object[]]$DomainControllers,

        [Parameter(Mandatory)]
        [object[]]$Users,

        [Parameter(Mandatory)]
        [object[]]$Computers,

        [Parameter(Mandatory)]
        [object[]]$Groups,

        [Parameter(Mandatory)]
        [object[]]$PrivilegedAccounts,

        [object[]]$Trusts,

        [object[]]$Findings
    )

    $reportPath = Join-Path $OutputPath "AD-Forest-Assessment.html"
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $uniquePrivilegedAccounts = @(
        $PrivilegedAccounts |
            Select-Object Domain, SamAccountName -Unique
    )

    $criticalFindings = @($Findings | Where-Object Severity -eq "Critical").Count
    $highFindings     = @($Findings | Where-Object Severity -eq "High").Count
    $mediumFindings   = @($Findings | Where-Object Severity -eq "Medium").Count
    $lowFindings      = @($Findings | Where-Object Severity -eq "Low").Count

    # Build environment overview tables

    $forestTable = $Forest |
        Select-Object `
            ForestName,
            ForestMode,
            RootDomain,
            GlobalCatalogCount,
            SchemaMaster,
            DomainNamingMaster |
        ConvertTo-Html -Fragment
    
    $domainTable = $Domains |
        Select-Object `
            DomainName,
            NetBIOSName,
            DomainMode,
            PDCEmulator,
            RIDMaster,
            InfrastructureMaster |
        ConvertTo-Html -Fragment
    
    $domainControllerTable = $DomainControllers |
        Select-Object `
            HostName,
            Domain,
            Site,
            IPv4Address,
            OperatingSystem,
            OperatingSystemVersion,
            IsGlobalCatalog,
            IsReadOnly |
        ConvertTo-Html -Fragment

    # Build security findings table

    if (@($Findings).Count -gt 0) {
    
        $findingsTable = $Findings |
            Select-Object `
                Severity,
                Category,
                ObjectName,
                Finding,
                Details,
                Recommendation |
            ConvertTo-Html -Fragment

    }
    else {

        $findingsTable = "<p>No security findings detected.</p>"
}

# Build user account health data

$totalUsers = @($Users).Count
$enabledUsers = @($Users | Where-Object Enabled).Count
$disabledUsers = @($Users | Where-Object { -not $_.Enabled }).Count
$neverLoggedOnUsers = @($Users | Where-Object NeverLoggedOn).Count
$inactiveUsers = @($Users | Where-Object InactiveOver90Days).Count
$passwordNeverExpiresUsers = @($Users | Where-Object PasswordNeverExpires).Count
$passwordNotRequiredUsers = @($Users | Where-Object PasswordNotRequired).Count
$lockedUsers = @($Users | Where-Object LockedOut).Count

$notableUsers = @(
    $Users | Where-Object {
        $_.NeverLoggedOn -or
        $_.InactiveOver90Days -or
        $_.PasswordNeverExpires -or
        $_.PasswordNotRequired -or
        $_.LockedOut
    }
)

if (@($notableUsers).Count -gt 0) {

    $notableUsersTable = $notableUsers |
        Select-Object `
            SamAccountName,
            DisplayName,
            Enabled,
            LastLogonDate,
            PasswordNeverExpires,
            PasswordNotRequired,
            LockedOut,
            NeverLoggedOn,
            InactiveOver90Days |
        ConvertTo-Html -Fragment

}
else {

    $notableUsersTable = "<p>No notable user account conditions detected.</p>"
}


# Build computer account health data

$totalComputers = @($Computers).Count
$enabledComputers = @($Computers | Where-Object Enabled).Count
$disabledComputers = @($Computers | Where-Object { -not $_.Enabled }).Count
$neverLoggedOnComputers = @($Computers | Where-Object NeverLoggedOn).Count
$inactiveComputers = @($Computers | Where-Object InactiveOver90Days).Count

$notableComputers = @(
    $Computers | Where-Object {
        -not $_.Enabled -or
        $_.NeverLoggedOn -or
        $_.InactiveOver90Days
    }
)

if (@($notableComputers).Count -gt 0) {

    $notableComputersTable = $notableComputers |
        Select-Object `
            ComputerName,
            Enabled,
            OperatingSystem,
            OperatingSystemVersion,
            LastLogonDate,
            PasswordLastSet,
            NeverLoggedOn,
            InactiveOver90Days |
        ConvertTo-Html -Fragment

}
else {

    $notableComputersTable = "<p>No notable computer account conditions detected.</p>"
}








    $html = @"
<!DOCTYPE html>
<html>
<head>

<meta charset="UTF-8">

<title>AD Forest Assessment</title>

<style>

body {
    font-family: Segoe UI, Arial, sans-serif;
    margin: 40px;
    background-color: #f5f5f5;
    color: #222;
}

h1 {
    color: #1f4e79;
}

h2 {
    margin-top: 35px;
    color: #1f4e79;
    border-bottom: 2px solid #1f4e79;
    padding-bottom: 5px;
}

h3 {
    margin-top: 25px;
    margin-bottom: 10px;
    color: #333;
    font-size: 17px;
}

.summary {
    display: flex;
    flex-wrap: wrap;
    gap: 15px;
}

.card {
    background: white;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 15px;
    width: 180px;
}

.card-title {
    color: #666;
    font-size: 13px;
}

.card-value {
    font-size: 26px;
    font-weight: bold;
    margin-top: 5px;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    margin-top: 15px;
}

th {
    background-color: #1f4e79;
    color: white;
    text-align: left;
    padding: 8px;
}

td {
    padding: 8px;
    border-bottom: 1px solid #ddd;
}

.findings-table {
    margin-top: 15px;
}

.findings-table td {
    vertical-align: top;
}

.findings-table th:nth-child(1) {
    width: 80px;
}

.findings-table th:nth-child(3) {
    width: 160px;
}

.critical {
    color: #b00020;
    font-weight: bold;
}

.high {
    color: #d35400;
    font-weight: bold;
}

.medium {
    color: #b7950b;
    font-weight: bold;
}

.low {
    color: #2471a3;
    font-weight: bold;
}

.footer {
    margin-top: 50px;
    color: #777;
    font-size: 12px;
}

</style>

</head>

<body>

<h1>Active Directory Forest Assessment</h1>

<p>
Forest: <strong>$($Forest.ForestName)</strong><br>
Assessment date: $reportDate
</p>


<h2>Executive Summary</h2>

<div class="summary">

<div class="card">
<div class="card-title">Domains</div>
<div class="card-value">$(@($Domains).Count)</div>
</div>

<div class="card">
<div class="card-title">Domain Controllers</div>
<div class="card-value">$(@($DomainControllers).Count)</div>
</div>

<div class="card">
<div class="card-title">Users</div>
<div class="card-value">$(@($Users).Count)</div>
</div>

<div class="card">
<div class="card-title">Computers</div>
<div class="card-value">$(@($Computers).Count)</div>
</div>

<div class="card">
<div class="card-title">Groups</div>
<div class="card-value">$(@($Groups).Count)</div>
</div>

<div class="card">
<div class="card-title">Privileged Accounts</div>
<div class="card-value">$(@($uniquePrivilegedAccounts).Count)</div>
</div>

<div class="card">
<div class="card-title">Trusts</div>
<div class="card-value">$(@($Trusts).Count)</div>
</div>

</div>


<h2>Environment Overview</h2>

<h3>Forest</h3>
$forestTable

<h3>Domains</h3>
$domainTable

<h3>Domain Controllers</h3>
$domainControllerTable


<h2>Security Findings</h2>

<div class="summary">

<div class="card">
<div class="card-title">Critical</div>
<div class="card-value critical">$criticalFindings</div>
</div>

<div class="card">
<div class="card-title">High</div>
<div class="card-value high">$highFindings</div>
</div>

<div class="card">
<div class="card-title">Medium</div>
<div class="card-value medium">$mediumFindings</div>
</div>

<div class="card">
<div class="card-title">Low</div>
<div class="card-value low">$lowFindings</div>
</div>

</div>

<h3>Finding Details</h3>

<div class="findings-table">
$findingsTable
</div>

<h2>User Account Health</h2>

<div class="summary">

<div class="card">
<div class="card-title">Total Users</div>
<div class="card-value">$totalUsers</div>
</div>

<div class="card">
<div class="card-title">Enabled</div>
<div class="card-value">$enabledUsers</div>
</div>

<div class="card">
<div class="card-title">Disabled</div>
<div class="card-value">$disabledUsers</div>
</div>

<div class="card">
<div class="card-title">Never Logged On</div>
<div class="card-value">$neverLoggedOnUsers</div>
</div>

<div class="card">
<div class="card-title">Inactive &gt; 90 Days</div>
<div class="card-value">$inactiveUsers</div>
</div>

<div class="card">
<div class="card-title">Password Never Expires</div>
<div class="card-value">$passwordNeverExpiresUsers</div>
</div>

<div class="card">
<div class="card-title">Password Not Required</div>
<div class="card-value">$passwordNotRequiredUsers</div>
</div>

<div class="card">
<div class="card-title">Locked</div>
<div class="card-value">$lockedUsers</div>
</div>

</div>

<h3>Notable User Accounts</h3>

<div class="findings-table">
$notableUsersTable
</div>

<h2>Computer Account Health</h2>

<div class="summary">

<div class="card">
<div class="card-title">Total Computers</div>
<div class="card-value">$totalComputers</div>
</div>

<div class="card">
<div class="card-title">Enabled</div>
<div class="card-value">$enabledComputers</div>
</div>

<div class="card">
<div class="card-title">Disabled</div>
<div class="card-value">$disabledComputers</div>
</div>

<div class="card">
<div class="card-title">Never Logged On</div>
<div class="card-value">$neverLoggedOnComputers</div>
</div>

<div class="card">
<div class="card-title">Inactive &gt; 90 Days</div>
<div class="card-value">$inactiveComputers</div>
</div>

</div>

<h3>Notable Computer Accounts</h3>

<div class="findings-table">
$notableComputersTable
</div>

<div class="footer">
Generated by AD Forest Assessment
</div>

</body>
</html>
"@

    Set-Content `
        -Path $reportPath `
        -Value $html `
        -Encoding UTF8

    return $reportPath
}

Export-ModuleMember -Function New-AssessmentHtmlReport