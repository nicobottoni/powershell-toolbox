function New-AssessmentHtmlReport {

    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$AssessmentStatus,

        [AllowEmptyCollection()]
        [string[]]$AssessmentWarnings,

        [Parameter(Mandatory)]
        [object]$AssessmentMetadata,

        [Parameter(Mandatory)]
        [int]$InactiveUserDays,

        [Parameter(Mandatory)]
        [int]$InactiveComputerDays,
        
        [Parameter(Mandatory)]
        [object]$Forest,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Domains,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$DomainControllers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Users,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Computers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Groups,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$PrivilegedAccounts,

        [AllowEmptyCollection()]
        [object[]]$Trusts,

        [AllowEmptyCollection()]
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

    $findingsTable = $findingsTable `
        -replace '<table>', '<table id="findingsTable" class="interactive-table">'

}
else {

    $findingsTable = "<p>No security findings detected.</p>"
}

# Build user account health data

$totalUsers = @($Users).Count
$enabledUsers = @($Users | Where-Object Enabled).Count
$disabledUsers = @($Users | Where-Object { -not $_.Enabled }).Count
$neverLoggedOnUsers = @($Users | Where-Object NeverLoggedOn).Count
$inactiveUsers = @($Users | Where-Object IsInactive).Count
$passwordNeverExpiresUsers = @($Users | Where-Object PasswordNeverExpires).Count
$passwordNotRequiredUsers = @($Users | Where-Object PasswordNotRequired).Count
$lockedUsers = @($Users | Where-Object LockedOut).Count

$notableUsers = @(
    $Users | Where-Object {
        $_.NeverLoggedOn -or
        $_.IsInactive -or
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
            IsInactive |
        ConvertTo-Html -Fragment

    $notableUsersTable = $notableUsersTable `
        -replace '<table>', '<table id="notableUsersTable" class="interactive-table">'

}
else {

    $notableUsersTable = "<p>No notable user account conditions detected.</p>"
}


# Build computer account health data

$totalComputers = @($Computers).Count
$enabledComputers = @($Computers | Where-Object Enabled).Count
$disabledComputers = @($Computers | Where-Object { -not $_.Enabled }).Count
$neverLoggedOnComputers = @($Computers | Where-Object NeverLoggedOn).Count
$inactiveComputers = @($Computers | Where-Object IsInactive).Count

$notableComputers = @(
    $Computers | Where-Object {
        -not $_.Enabled -or
        $_.NeverLoggedOn -or
        $_.IsInactive
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
            IsInactive |
        ConvertTo-Html -Fragment

    $notableComputersTable = $notableComputersTable `
        -replace '<table>', '<table id="notableComputersTable" class="interactive-table">'

}
else {

    $notableComputersTable = "<p>No notable computer account conditions detected.</p>"
}


# Build group health data

$totalGroups = @($Groups).Count
$securityGroups = @($Groups | Where-Object GroupCategory -eq "Security").Count
$distributionGroups = @($Groups | Where-Object GroupCategory -eq "Distribution").Count
$globalGroups = @($Groups | Where-Object GroupScope -eq "Global").Count
$universalGroups = @($Groups | Where-Object GroupScope -eq "Universal").Count
$domainLocalGroups = @($Groups | Where-Object GroupScope -eq "DomainLocal").Count
$emptyGroups = @($Groups | Where-Object IsEmpty).Count
$groupsWithoutDescription = @($Groups | Where-Object { -not $_.HasDescription }).Count
$groupsWithNesting = @($Groups | Where-Object { $_.NestedGroupCount -gt 0 }).Count
$groupQueryErrors = @($Groups | Where-Object { -not $_.MembershipQuerySuccessful }).Count

$notableGroups = @(
    $Groups | Where-Object {
        $_.IsEmpty -or
        -not $_.HasDescription -or
        $_.NestedGroupCount -gt 0
    }
)

if (@($notableGroups).Count -gt 0) {

    $notableGroupsTable = $notableGroups |
        Select-Object `
            GroupName,
            GroupCategory,
            GroupScope,
            MemberCount,
            NestedGroupCount,
            HasDescription,
            IsEmpty |
        ConvertTo-Html -Fragment

    $notableGroupsTable = $notableGroupsTable `
        -replace '<table>', '<table id="notableGroupsTable" class="interactive-table">'

}
else {

    $notableGroupsTable = "<p>No notable group conditions detected.</p>"
}

# Build privileged access data

$totalPrivilegedMemberships = @($PrivilegedAccounts).Count

$directPrivilegedMemberships = @(
    $PrivilegedAccounts |
        Where-Object MembershipType -eq "Direct"
).Count

$indirectPrivilegedMemberships = @(
    $PrivilegedAccounts |
        Where-Object MembershipType -eq "Indirect"
).Count

$uniquePrivilegedAccounts = @(
    $PrivilegedAccounts |
        Group-Object Domain, SamAccountName |
        ForEach-Object {
            $_.Group | Select-Object -First 1
        }
)

$totalUniquePrivilegedAccounts = @(
    $uniquePrivilegedAccounts
).Count

$enabledPrivilegedAccounts = @(
    $uniquePrivilegedAccounts |
        Where-Object Enabled
).Count

$disabledPrivilegedAccounts = @(
    $uniquePrivilegedAccounts |
        Where-Object { -not $_.Enabled }
).Count

$privilegedPasswordNeverExpires = @(
    $uniquePrivilegedAccounts |
        Where-Object PasswordNeverExpires
).Count

$privilegedPasswordNotRequired = @(
    $uniquePrivilegedAccounts |
        Where-Object PasswordNotRequired
).Count

if (@($PrivilegedAccounts).Count -gt 0) {

    $privilegedAccountsTable = $PrivilegedAccounts |
        Sort-Object PrivilegedGroup, MembershipType, SamAccountName |
        Select-Object `
            PrivilegedGroup,
            PrivilegedGroupKey,
            MembershipType,
            SamAccountName,
            Enabled,
            LastLogonDate,
            PasswordLastSet,
            PasswordNeverExpires,
            PasswordNotRequired |
        ConvertTo-Html -Fragment

    $privilegedAccountsTable = $privilegedAccountsTable `
        -replace '<table>', '<table id="privilegedAccountsTable" class="interactive-table">'

}
else {

    $privilegedAccountsTable = "<p>No privileged user accounts detected.</p>"
}



# Build trust detail data

$totalTrusts = @($Trusts).Count

$bidirectionalTrusts = @(
    $Trusts |
        Where-Object Direction -eq "Bidirectional"
).Count

$inboundTrusts = @(
    $Trusts |
        Where-Object Direction -eq "Inbound"
).Count

$outboundTrusts = @(
    $Trusts |
        Where-Object Direction -eq "Outbound"
).Count

$forestTrusts = @(
    $Trusts |
        Where-Object ForestTransitive
).Count

if (@($Trusts).Count -gt 0) {

    $trustsTable = $Trusts |
        Select-Object `
            Source,
            Target,
            Direction,
            TrustType,
            ForestTransitive,
            IntraForest,
            SelectiveAuthentication,
            SIDFilteringForestAware,
            SIDFilteringQuarantined |
        ConvertTo-Html -Fragment

    $trustsTable = $trustsTable `
        -replace '<table>', '<table id="trustsTable" class="interactive-table">'

}
else {

    $trustsTable = "<p>No domain or forest trusts detected.</p>"
}

# Build assessment status information

switch ($AssessmentStatus) {

    "Completed" {
        $statusText = "Completed"
        $statusClass = "status-success"
    }

    "CompletedWithWarnings" {
        $statusText = "Completed with Warnings"
        $statusClass = "status-warning"
    }

    "Failed" {
        $statusText = "Failed"
        $statusClass = "status-failed"
    }

    default {
        $statusText = $AssessmentStatus
        $statusClass = "status-warning"
    }
}

if (@($AssessmentWarnings).Count -gt 0) {

    $warningItems = @(
        foreach ($warning in $AssessmentWarnings) {
            "<li>$warning</li>"
        }
    ) -join ""

    $warningsHtml = @"
<div class="assessment-warnings">
    <strong>Warnings</strong>
    <ul>
        $warningItems
    </ul>
</div>
"@

}
else {

    $warningsHtml = ""
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

.assessment-status {
    margin-top: 20px;
    margin-bottom: 20px;
    padding: 15px;
    background: white;
    border: 1px solid #ddd;
    border-left-width: 5px;
    border-radius: 6px;
}

.status-success {
    border-left-color: #2e7d32;
}

.status-warning {
    border-left-color: #d97706;
}

.status-failed {
    border-left-color: #b00020;
}

.status-value {
    font-size: 18px;
    font-weight: bold;
}

.status-success .status-value {
    color: #2e7d32;
}

.status-warning .status-value {
    color: #d97706;
}

.status-failed .status-value {
    color: #b00020;
}

.assessment-warnings {
    margin-top: 12px;
    color: #555;
}

.assessment-warnings ul {
    margin-top: 6px;
    margin-bottom: 0;
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

.table-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: end;
    flex-wrap: wrap;
    gap: 15px;
    margin-top: 15px;
    margin-bottom: 10px;
}

.table-length,
.table-actions {
    display: flex;
    align-items: center;
    gap: 8px;
}

.table-toolbar label {
    font-size: 13px;
    color: #555;
}

.table-toolbar select,
.table-toolbar input {
    border: 1px solid #bbb;
    border-radius: 4px;
    padding: 7px 9px;
    background-color: white;
    color: #222;
}

.table-toolbar input {
    min-width: 220px;
}

.table-toolbar button {
    border: 1px solid #1f4e79;
    border-radius: 4px;
    padding: 7px 12px;
    background-color: #1f4e79;
    color: white;
    cursor: pointer;
}

.table-toolbar button:hover {
    background-color: #163a5b;
}

.table-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 15px;
    margin-top: 12px;
}

.table-info {
    color: #555;
    font-size: 13px;
}

.table-pagination {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
}

.table-pagination button {
    min-width: 34px;
    border: 1px solid #ccc;
    border-radius: 4px;
    padding: 6px 9px;
    background-color: white;
    color: #1f4e79;
    cursor: pointer;
}

.table-pagination button:hover:not(:disabled) {
    background-color: #e8f0f7;
}

.table-pagination button.active {
    background-color: #1f4e79;
    border-color: #1f4e79;
    color: white;
}

.table-pagination button:disabled {
    color: #999;
    cursor: default;
    background-color: #eee;
}

@media (max-width: 800px) {
    .table-toolbar,
    .table-footer {
        align-items: stretch;
        flex-direction: column;
    }

    .table-actions {
        flex-wrap: wrap;
    }

    .table-toolbar input {
        min-width: 0;
        flex: 1;
    }
}

</style>

</head>

<body>

<h1>Active Directory Forest Assessment</h1>

<p>
Forest: <strong>$($Forest.ForestName)</strong><br>
Assessment date: $reportDate
</p>

<div class="assessment-status $statusClass">

<div class="card-title">Assessment Status</div>

<div class="status-value">
$statusText
</div>

$warningsHtml

</div>

<h2>Assessment Information</h2>

<table>
<tr>
    <th>Property</th>
    <th>Value</th>
</tr>
<tr>
    <td>Version</td>
    <td>$($AssessmentMetadata.Version)</td>
</tr>
<tr>
    <td>Assessment Host</td>
    <td>$($AssessmentMetadata.HostName)</td>
</tr>
<tr>
    <td>PowerShell Version</td>
    <td>$($AssessmentMetadata.PowerShellVersion)</td>
</tr>
<tr>
    <td>Started</td>
    <td>$($AssessmentMetadata.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))</td>
</tr>
<tr>
    <td>Completed</td>
    <td>$($AssessmentMetadata.EndTime.ToString("yyyy-MM-dd HH:mm:ss"))</td>
</tr>
<tr>
    <td>Duration</td>
    <td>$($AssessmentMetadata.Duration.ToString("hh\:mm\:ss"))</td>
</tr>
</table>

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

<div class="table-toolbar" id="findingsToolbar">

    <div class="table-length">
        <label for="findingsPageSize">Rows per page:</label>

        <select id="findingsPageSize">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
        </select>
    </div>

    <div class="table-actions">
        <label for="findingsSearch">Search:</label>

        <input
            id="findingsSearch"
            type="search"
            placeholder="Search security findings">

        <button
            type="button"
            id="findingsDownload">
            Download CSV
        </button>
    </div>

</div>

<div class="findings-table">
$findingsTable
</div>

<div class="table-footer" id="findingsFooter">

    <div
        id="findingsInfo"
        class="table-info">
    </div>

    <div
        id="findingsPagination"
        class="table-pagination">
    </div>

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
<div class="card-title">Inactive &gt; $InactiveUserDays Days</div>
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

<div class="table-toolbar" id="notableUsersToolbar">

    <div class="table-length">
        <label for="notableUsersPageSize">Rows per page:</label>

        <select id="notableUsersPageSize">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
        </select>
    </div>

    <div class="table-actions">
        <label for="notableUsersSearch">Search:</label>

        <input
            id="notableUsersSearch"
            type="search"
            placeholder="Search user accounts">

        <button
            type="button"
            id="notableUsersDownload">
            Download CSV
        </button>
    </div>

</div>

<div class="findings-table">
$notableUsersTable
</div>

<div class="table-footer" id="notableUsersFooter">

    <div
        id="notableUsersInfo"
        class="table-info">
    </div>

    <div
        id="notableUsersPagination"
        class="table-pagination">
    </div>

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
<div class="card-title">Inactive &gt; $InactiveComputerDays Days</div>
<div class="card-value">$inactiveComputers</div>
</div>

</div>

<h3>Notable Computer Accounts</h3>

<div class="table-toolbar" id="notableComputersToolbar">

    <div class="table-length">
        <label for="notableComputersPageSize">Rows per page:</label>

        <select id="notableComputersPageSize">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
        </select>
    </div>

    <div class="table-actions">
        <label for="notableComputersSearch">Search:</label>

        <input
            id="notableComputersSearch"
            type="search"
            placeholder="Search computer accounts">

        <button
            type="button"
            id="notableComputersDownload">
            Download CSV
        </button>
    </div>

</div>

<div class="findings-table">
$notableComputersTable
</div>

<div class="table-footer" id="notableComputersFooter">

    <div
        id="notableComputersInfo"
        class="table-info">
    </div>

    <div
        id="notableComputersPagination"
        class="table-pagination">
    </div>

</div>

<h2>Group Health</h2>

<div class="summary">

<div class="card">
<div class="card-title">Total Groups</div>
<div class="card-value">$totalGroups</div>
</div>

<div class="card">
<div class="card-title">Security Groups</div>
<div class="card-value">$securityGroups</div>
</div>

<div class="card">
<div class="card-title">Distribution Groups</div>
<div class="card-value">$distributionGroups</div>
</div>

<div class="card">
<div class="card-title">Global Groups</div>
<div class="card-value">$globalGroups</div>
</div>

<div class="card">
<div class="card-title">Universal Groups</div>
<div class="card-value">$universalGroups</div>
</div>

<div class="card">
<div class="card-title">Domain Local Groups</div>
<div class="card-value">$domainLocalGroups</div>
</div>

<div class="card">
<div class="card-title">Empty Groups</div>
<div class="card-value">$emptyGroups</div>
</div>

<div class="card">
<div class="card-title">Without Description</div>
<div class="card-value">$groupsWithoutDescription</div>
</div>

<div class="card">
<div class="card-title">Groups with Nesting</div>
<div class="card-value">$groupsWithNesting</div>
</div>

<div class="card">
<div class="card-title">Membership Query Errors</div>
<div class="card-value">$groupQueryErrors</div>
</div>

</div>

<h3>Notable Groups</h3>

<div class="table-toolbar" id="notableGroupsToolbar">

    <div class="table-length">
        <label for="notableGroupsPageSize">Rows per page:</label>

        <select id="notableGroupsPageSize">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
        </select>
    </div>

    <div class="table-actions">
        <label for="notableGroupsSearch">Search:</label>

        <input
            id="notableGroupsSearch"
            type="search"
            placeholder="Search groups">

        <button
            type="button"
            id="notableGroupsDownload">
            Download CSV
        </button>
    </div>

</div>

<div class="findings-table">
$notableGroupsTable
</div>

<div class="table-footer" id="notableGroupsFooter">

    <div
        id="notableGroupsInfo"
        class="table-info">
    </div>

    <div
        id="notableGroupsPagination"
        class="table-pagination">
    </div>

</div>

<h2>Privileged Access</h2>

<div class="summary">

<div class="card">
<div class="card-title">Unique Privileged Accounts</div>
<div class="card-value">$totalUniquePrivilegedAccounts</div>
</div>

<div class="card">
<div class="card-title">Privileged Memberships</div>
<div class="card-value">$totalPrivilegedMemberships</div>
</div>

<div class="card">
<div class="card-title">Direct Memberships</div>
<div class="card-value">$directPrivilegedMemberships</div>
</div>

<div class="card">
<div class="card-title">Indirect Memberships</div>
<div class="card-value">$indirectPrivilegedMemberships</div>
</div>

<div class="card">
<div class="card-title">Enabled Accounts</div>
<div class="card-value">$enabledPrivilegedAccounts</div>
</div>

<div class="card">
<div class="card-title">Disabled Accounts</div>
<div class="card-value">$disabledPrivilegedAccounts</div>
</div>

<div class="card">
<div class="card-title">Password Never Expires</div>
<div class="card-value">$privilegedPasswordNeverExpires</div>
</div>

<div class="card">
<div class="card-title">Password Not Required</div>
<div class="card-value">$privilegedPasswordNotRequired</div>
</div>

</div>

<h3>Privileged Account Memberships</h3>

<div class="table-toolbar" id="privilegedAccountsToolbar">

    <div class="table-length">
        <label for="privilegedAccountsPageSize">Rows per page:</label>

        <select id="privilegedAccountsPageSize">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
        </select>
    </div>

    <div class="table-actions">
        <label for="privilegedAccountsSearch">Search:</label>

        <input
            id="privilegedAccountsSearch"
            type="search"
            placeholder="Search privileged accounts">

        <button
            type="button"
            id="privilegedAccountsDownload">
            Download CSV
        </button>
    </div>

</div>

<div class="findings-table">
$privilegedAccountsTable
</div>

<div class="table-footer" id="privilegedAccountsFooter">

    <div
        id="privilegedAccountsInfo"
        class="table-info">
    </div>

    <div
        id="privilegedAccountsPagination"
        class="table-pagination">
    </div>

</div>

<h2>Trust Details</h2>

<div class="summary">

<div class="card">
<div class="card-title">Total Trusts</div>
<div class="card-value">$totalTrusts</div>
</div>

<div class="card">
<div class="card-title">Bidirectional</div>
<div class="card-value">$bidirectionalTrusts</div>
</div>

<div class="card">
<div class="card-title">Inbound</div>
<div class="card-value">$inboundTrusts</div>
</div>

<div class="card">
<div class="card-title">Outbound</div>
<div class="card-value">$outboundTrusts</div>
</div>

<div class="card">
<div class="card-title">Forest Trusts</div>
<div class="card-value">$forestTrusts</div>
</div>

</div>

<h3>Trust Relationships</h3>

<div class="table-toolbar" id="trustsToolbar">

    <div class="table-length">
        <label for="trustsPageSize">Rows per page:</label>

        <select id="trustsPageSize">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
        </select>
    </div>

    <div class="table-actions">
        <label for="trustsSearch">Search:</label>

        <input
            id="trustsSearch"
            type="search"
            placeholder="Search trusts">

        <button
            type="button"
            id="trustsDownload">
            Download CSV
        </button>
    </div>

</div>

<div class="findings-table">
$trustsTable
</div>

<div class="table-footer" id="trustsFooter">

    <div
        id="trustsInfo"
        class="table-info">
    </div>

    <div
        id="trustsPagination"
        class="table-pagination">
    </div>

</div>




<div class="footer">
Generated by AD Forest Assessment
</div>

<script>
(function () {
    "use strict";

    function initializeInteractiveTable(options) {
        const table = document.getElementById(options.tableId);
        const pageSizeSelect = document.getElementById(options.pageSizeId);
        const searchInput = document.getElementById(options.searchId);
        const downloadButton = document.getElementById(options.downloadId);
        const information = document.getElementById(options.infoId);
        const pagination = document.getElementById(options.paginationId);
        const toolbar = document.getElementById(options.toolbarId);
        const footer = document.getElementById(options.footerId);


        if (!table) {

            if (toolbar) {
                toolbar.style.display = "none";
            }
        
            if (footer) {
                footer.style.display = "none";
            }
        
            return;
        }
        
        if (
            !pageSizeSelect ||
            !searchInput ||
            !downloadButton ||
            !information ||
            !pagination
        ) {
            return;
        }

        const allRows = Array.from(table.rows);

        if (allRows.length === 0) {
            return;
        }

        const headerRow = allRows[0];
        const rows = allRows.slice(1);

        let filteredRows = rows.slice();
        let currentPage = 1;
        let pageSize = parseInt(pageSizeSelect.value, 10) || 25;

        function getCellText(row) {
            return Array.from(row.cells)
                .map(function (cell) {
                    return cell.textContent.trim();
                })
                .join(" ")
                .toLowerCase();
        }

        function updateFilter() {
            const searchTerm = searchInput.value
                .trim()
                .toLowerCase();

            if (!searchTerm) {
                filteredRows = rows.slice();
            }
            else {
                filteredRows = rows.filter(function (row) {
                    return getCellText(row).includes(searchTerm);
                });
            }

            currentPage = 1;
            render();
        }

        function createPageButton(label, page, disabled, active) {
            const button = document.createElement("button");

            button.type = "button";
            button.textContent = label;
            button.disabled = disabled;

            if (active) {
                button.classList.add("active");
            }

            button.addEventListener("click", function () {
                currentPage = page;
                render();
            });

            return button;
        }

        function renderPagination(pageCount) {
            pagination.replaceChildren();

            pagination.appendChild(
                createPageButton(
                    "Previous",
                    Math.max(1, currentPage - 1),
                    currentPage === 1,
                    false
                )
            );

            let firstPage = Math.max(1, currentPage - 2);
            let lastPage = Math.min(pageCount, firstPage + 4);

            firstPage = Math.max(1, lastPage - 4);

            for (let page = firstPage; page <= lastPage; page++) {
                pagination.appendChild(
                    createPageButton(
                        String(page),
                        page,
                        false,
                        page === currentPage
                    )
                );
            }

            pagination.appendChild(
                createPageButton(
                    "Next",
                    Math.min(pageCount, currentPage + 1),
                    currentPage === pageCount || pageCount === 0,
                    false
                )
            );
        }

        function render() {
            pageSize = parseInt(pageSizeSelect.value, 10) || 25;

            const totalRows = filteredRows.length;
            const pageCount = Math.max(1, Math.ceil(totalRows / pageSize));

            if (currentPage > pageCount) {
                currentPage = pageCount;
            }

            const startIndex = (currentPage - 1) * pageSize;
            const endIndex = Math.min(startIndex + pageSize, totalRows);

            rows.forEach(function (row) {
                row.hidden = true;
            });

            filteredRows
                .slice(startIndex, endIndex)
                .forEach(function (row) {
                    row.hidden = false;
                });

            if (totalRows === 0) {
                information.textContent = "Showing 0 of 0 rows";
            }
            else {
                information.textContent =
                    "Showing " +
                    (startIndex + 1) +
                    " to " +
                    endIndex +
                    " of " +
                    totalRows +
                    " rows";
            }

            renderPagination(pageCount);
        }

        function escapeCsvValue(value) {
            const normalizedValue = value
                .replace(/\r?\n|\r/g, " ")
                .trim();

            return '"' + normalizedValue.replace(/"/g, '""') + '"';
        }

        function downloadCsv() {
            const headerCells = Array.from(headerRow.cells);

            const csvRows = [];

            if (headerCells.length > 0) {
                csvRows.push(
                    headerCells
                        .map(function (cell) {
                            return escapeCsvValue(cell.textContent);
                        })
                        .join(",")
                );
            }

            filteredRows.forEach(function (row) {
                csvRows.push(
                    Array.from(row.cells)
                        .map(function (cell) {
                            return escapeCsvValue(cell.textContent);
                        })
                        .join(",")
                );
            });

            const csvContent = "\uFEFF" + csvRows.join("\r\n");
            const blob = new Blob(
                [csvContent],
                { type: "text/csv;charset=utf-8" }
            );

            const downloadUrl = URL.createObjectURL(blob);
            const link = document.createElement("a");

            link.href = downloadUrl;
            link.download = options.fileName;
            document.body.appendChild(link);
            link.click();
            link.remove();

            URL.revokeObjectURL(downloadUrl);
        }

        pageSizeSelect.addEventListener("change", function () {
            currentPage = 1;
            render();
        });

        searchInput.addEventListener("input", updateFilter);
        downloadButton.addEventListener("click", downloadCsv);

        render();
    }

    initializeInteractiveTable({
        tableId: "notableUsersTable",
        pageSizeId: "notableUsersPageSize",
        searchId: "notableUsersSearch",
        downloadId: "notableUsersDownload",
        infoId: "notableUsersInfo",
        paginationId: "notableUsersPagination",
        toolbarId: "notableUsersToolbar",
        footerId: "notableUsersFooter",
        fileName: "NotableUsers.csv"
    });

    initializeInteractiveTable({
        tableId: "notableComputersTable",
        pageSizeId: "notableComputersPageSize",
        searchId: "notableComputersSearch",
        downloadId: "notableComputersDownload",
        infoId: "notableComputersInfo",
        paginationId: "notableComputersPagination",
        toolbarId: "notableComputersToolbar",
        footerId: "notableComputersFooter",
        fileName: "NotableComputers.csv"
    });

    initializeInteractiveTable({
        tableId: "notableGroupsTable",
        pageSizeId: "notableGroupsPageSize",
        searchId: "notableGroupsSearch",
        downloadId: "notableGroupsDownload",
        infoId: "notableGroupsInfo",
        paginationId: "notableGroupsPagination",
        toolbarId: "notableGroupsToolbar",
        footerId: "notableGroupsFooter",
        fileName: "NotableGroups.csv"
    });

    initializeInteractiveTable({
        tableId: "privilegedAccountsTable",
        pageSizeId: "privilegedAccountsPageSize",
        searchId: "privilegedAccountsSearch",
        downloadId: "privilegedAccountsDownload",
        infoId: "privilegedAccountsInfo",
        paginationId: "privilegedAccountsPagination",
        toolbarId: "privilegedAccountsToolbar",
        footerId: "privilegedAccountsFooter",
        fileName: "PrivilegedAccounts.csv"
    });

    initializeInteractiveTable({
        tableId: "trustsTable",
        pageSizeId: "trustsPageSize",
        searchId: "trustsSearch",
        downloadId: "trustsDownload",
        infoId: "trustsInfo",
        paginationId: "trustsPagination",
        toolbarId: "trustsToolbar",
        footerId: "trustsFooter",
        fileName: "Trusts.csv"
    });

    initializeInteractiveTable({
        tableId: "findingsTable",
        pageSizeId: "findingsPageSize",
        searchId: "findingsSearch",
        downloadId: "findingsDownload",
        infoId: "findingsInfo",
        paginationId: "findingsPagination",
        toolbarId: "findingsToolbar",
        footerId: "findingsFooter",
        fileName: "SecurityFindings.csv"
    });

})();
</script>

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