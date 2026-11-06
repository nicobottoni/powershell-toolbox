# ============================================
# Administrative Unit - Role Assignment Report
# ============================================

# Check required Microsoft Graph modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users"
)

foreach ($Module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Write-Host "Missing module: $Module" -ForegroundColor Yellow
        Write-Host "Installing module..." -ForegroundColor Yellow

        Install-Module $Module -Scope CurrentUser -Force
    }
}

# Import modules
foreach ($Module in $RequiredModules) {
    Import-Module $Module
}

# Connect to Microsoft Graph
Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

Connect-MgGraph -Scopes `
    "RoleManagement.Read.Directory",
    "Directory.Read.All" `
    -NoWelcome

# Ask for Administrative Unit
Write-Host ""
$AUName = Read-Host "Enter the name of the Administrative Unit"

# Escape single quotes for OData filter
$EscapedAUName = $AUName.Replace("'","''")

# Find Administrative Unit
$AU = Get-MgDirectoryAdministrativeUnit `
    -Filter "displayName eq '$EscapedAUName'"

if (-not $AU) {
    Write-Host ""
    Write-Host "Administrative Unit '$AUName' was not found." -ForegroundColor Red
    return
}

if (@($AU).Count -gt 1) {
    Write-Host ""
    Write-Host "Multiple Administrative Units with this name were found." -ForegroundColor Red
    $AU | Select-Object DisplayName, Id | Format-Table -AutoSize
    return
}

Write-Host ""
Write-Host "Administrative Unit found:" -ForegroundColor Green
Write-Host "Name: $($AU.DisplayName)"
Write-Host "ID:   $($AU.Id)"

# Get scoped role assignments
Write-Host ""
Write-Host "Reading role assignments..." -ForegroundColor Cyan

$Uri = "https://graph.microsoft.com/beta/administrativeUnits/$($AU.Id)/scopedRoleMembers"

$Assignments = @()

do {
    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri $Uri

    if ($Response.value) {
        $Assignments += $Response.value
    }

    $Uri = $Response.'@odata.nextLink'

} while ($Uri)

if (-not $Assignments) {
    Write-Host ""
    Write-Host "No scoped role assignments were found." -ForegroundColor Yellow
    return
}

# Resolve assignments
$Results = foreach ($Assignment in $Assignments) {

    $MemberId = $Assignment.roleMemberInfo.id
    $RoleId   = $Assignment.roleId

    # Resolve role
    try {
        $Role = Get-MgDirectoryRole `
            -DirectoryRoleId $RoleId `
            -ErrorAction Stop

        $RoleName = $Role.DisplayName
    }
    catch {
        $RoleName = "Unknown Role"
    }

    # Resolve directory object
    try {

        $Object = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$MemberId"

        $ObjectType = $Object.'@odata.type' -replace '#microsoft.graph.', ''

        $DisplayName = $Object.displayName

        if ($Object.userPrincipalName) {
            $Identifier = $Object.userPrincipalName
        }
        elseif ($Object.mail) {
            $Identifier = $Object.mail
        }
        elseif ($Object.appId) {
            $Identifier = $Object.appId
        }
        else {
            $Identifier = $MemberId
        }
    }
    catch {
        $ObjectType  = "Unknown"
        $DisplayName = "Unable to resolve"
        $Identifier  = $MemberId
    }

    [PSCustomObject]@{
        AdministrativeUnit = $AU.DisplayName
        Role               = $RoleName
        Type               = $ObjectType
        Name               = $DisplayName
        Identifier         = $Identifier
    }
}

# Display results
Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host " Administrative Unit: $($AU.DisplayName)" -ForegroundColor Cyan
Write-Host " Role Assignments:    $($Results.Count)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host ""

$Results |
    Sort-Object Role, Name |
    Format-Table Role, Type, Name, Identifier -AutoSize