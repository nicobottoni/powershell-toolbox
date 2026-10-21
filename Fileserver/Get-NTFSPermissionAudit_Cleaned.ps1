#requires -Version 5.1
#requires -Modules ActiveDirectory

<#!
.SYNOPSIS
    NTFS permission audit for file servers.

.DESCRIPTION
    This script scans NTFS ACLs for folders and, optionally, files and derives
    a readable user access map from direct assignments and AD group membership.

    The output contains:
    - raw ACL data
    - group expansion structure
    - direct and transitive user access rows
    - effective per-user summary per item
    - unresolved identities
    - scan errors
    - SHA256 checksums for all generated CSV files

.NOTES
    Scope of this audit:
    - NTFS ACLs on the file system
    - direct user access via ACEs
    - AD security group expansion
    - nested group members
    - allow and deny rights
    - unresolved identities and failed scans

    Not included in this audit:
    - SMB share permissions
    - Dynamic Access Control (DAC)
    - Central Access Policies (CAP)
    - user rights such as Backup Operators
    - Access Based Enumeration (ABE)
    - NTFS permissions derived from SIDHistory
    - local groups on remote file servers
    - Kerberos session tokens
    - application permissions outside the file system

    The column DerivedRights is a technical ACL derivation and is not a substitute
    for a real Windows effective access evaluation for a specific user token.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RootPath = "\\server\share\wantedfolder",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "C:\temp\Berechtigungspruefung",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeFiles,

    [Parameter(Mandatory = $false)]
    [string]$ExcludedUsersCsv,

    [Parameter(Mandatory = $false)]
    [switch]$ExcludeDisabledUsers,

    [Parameter(Mandatory = $false)]
    [switch]$OnlyPermissionBoundaries,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludedAclGroups = @(),

    [Parameter(Mandatory = $false)]
    [char]$CsvDelimiter = ';'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module ActiveDirectory -ErrorAction Stop

# ------------------------------------------------------------
# Initialization
# ------------------------------------------------------------

$ScriptStart = Get-Date
$RunId = $ScriptStart.ToString('yyyyMMdd_HHmmss')
$ComputerName = $env:COMPUTERNAME
$ExecutingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$AclRaw = [System.Collections.Generic.List[object]]::new()
$GroupStructure = [System.Collections.Generic.List[object]]::new()
$UserAccess = [System.Collections.Generic.List[object]]::new()
$UnresolvedIdentities = [System.Collections.Generic.List[object]]::new()
$ScanErrors = [System.Collections.Generic.List[object]]::new()

$IdentityCache = @{}
$GroupExpansionCache = @{}
$ExcludedUsers = @{}
$script:UnresolvedIdentityKeys = @{}

$PermissionBoundaryCount = 0
$InheritedOnlySkippedCount = 0
$ProtectedAclCount = 0
$ExplicitAclCount = 0

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$Timestamp][$Level] $Message"
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $InvalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()

    foreach ($Character in $InvalidCharacters) {
        $Name = $Name.Replace($Character, '_')
    }

    return $Name
}

function Get-RightsMask {
    param(
        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemRights]$Rights
    )

    $SignedValue = [int64]$Rights
    return $SignedValue -band 0xFFFFFFFFL
}

function Convert-RightsMaskToText {
    param(
        [Parameter(Mandatory)]
        [uint32]$Mask
    )

    if ($Mask -eq 0) {
        return 'None'
    }

    try {
        return ([System.Security.AccessControl.FileSystemRights]$Mask).ToString()
    }
    catch {
        return ('0x{0:X8}' -f $Mask)
    }
}

function Add-ScanError {
    param(
        [string]$Stage,
        [string]$Path,
        [string]$Identity,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $ScanErrors.Add([pscustomobject][ordered]@{
        Timestamp             = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Stage                 = $Stage
        Path                  = $Path
        Identity              = $Identity
        ErrorMessage          = $ErrorRecord.Exception.Message
        ExceptionType         = $ErrorRecord.Exception.GetType().FullName
        FullyQualifiedErrorId = $ErrorRecord.FullyQualifiedErrorId
    })
}

function Add-UnresolvedIdentity {
    param(
        [string]$Identity,
        [string]$SID,
        [string]$Reason,
        [string]$Path
    )

    $Key = "$Identity|$SID|$Reason|$Path"

    if (-not $script:UnresolvedIdentityKeys) {
        $script:UnresolvedIdentityKeys = @{}
    }

    if (-not $script:UnresolvedIdentityKeys.ContainsKey($Key)) {
        $script:UnresolvedIdentityKeys[$Key] = $true

        $UnresolvedIdentities.Add([pscustomobject][ordered]@{
            Identity = $Identity
            SID      = $SID
            Reason   = $Reason
            Path     = $Path
        })
    }
}

function Initialize-ExcludedUsers {
    if ([string]::IsNullOrWhiteSpace($ExcludedUsersCsv)) {
        return
    }

    if (-not (Test-Path -LiteralPath $ExcludedUsersCsv)) {
        throw "The exclusion file was not found: $ExcludedUsersCsv"
    }

    Write-Log "Reading excluded users from $ExcludedUsersCsv"

    $Entries = Import-Csv -LiteralPath $ExcludedUsersCsv -Delimiter $CsvDelimiter

    foreach ($Entry in $Entries) {
        foreach ($PropertyName in @('SamAccountName', 'UserPrincipalName', 'SID')) {
            if (
                $Entry.PSObject.Properties.Name -contains $PropertyName -and
                -not [string]::IsNullOrWhiteSpace($Entry.$PropertyName)
            ) {
                $ExcludedUsers[$Entry.$PropertyName.Trim().ToLowerInvariant()] = $true
            }
        }
    }

    Write-Log "$($ExcludedUsers.Count) excluded values were loaded."
}

function Test-UserExcluded {
    param(
        [string]$SamAccountName,
        [string]$UserPrincipalName,
        [string]$SID
    )

    foreach ($Value in @($SamAccountName, $UserPrincipalName, $SID)) {
        if (
            -not [string]::IsNullOrWhiteSpace($Value) -and
            $ExcludedUsers.ContainsKey($Value.Trim().ToLowerInvariant())
        ) {
            return $true
        }
    }

    return $false
}

function Resolve-AclIdentity {
    param(
        [Parameter(Mandatory)]
        [string]$IdentityReference,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($IdentityReference)) {
        return [pscustomobject]@{
            OriginalIdentity   = $null
            SID               = $null
            ObjectType        = 'Unknown'
            Name              = $null
            SamAccountName    = $null
            UserPrincipalName = $null
            DistinguishedName = $null
            Enabled           = $null
            DomainObject      = $false
            ResolutionStatus  = 'Unresolved'
        }
    }

    $CacheKey = $IdentityReference.ToLowerInvariant()

    if ($IdentityCache.ContainsKey($CacheKey)) {
        return $IdentityCache[$CacheKey]
    }

    $Result = [ordered]@{
        OriginalIdentity   = $IdentityReference
        SID               = $null
        ObjectType        = 'Unknown'
        Name              = $IdentityReference
        SamAccountName    = $null
        UserPrincipalName = $null
        DistinguishedName = $null
        Enabled           = $null
        DomainObject      = $false
        ResolutionStatus  = 'Unresolved'
    }

    try {
        $NTAccount = [System.Security.Principal.NTAccount]::new($IdentityReference)
        $SIDObject = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])
        $Result.SID = $SIDObject.Value
    }
    catch {
        if ($IdentityReference -match '^S-\d-\d+-.+') {
            $Result.SID = $IdentityReference
        }
    }

    if ($Result.SID) {
        try {
            $User = Get-ADUser -Identity $Result.SID -Properties DisplayName, UserPrincipalName, Enabled, SID -ErrorAction Stop

            $Result.ObjectType        = 'User'
            $Result.Name              = $User.Name
            $Result.SamAccountName    = $User.SamAccountName
            $Result.UserPrincipalName = $User.UserPrincipalName
            $Result.DistinguishedName = $User.DistinguishedName
            $Result.Enabled           = $User.Enabled
            $Result.DomainObject      = $true
            $Result.ResolutionStatus  = 'Resolved'

            $ResolvedResult = [pscustomobject]$Result
            $IdentityCache[$CacheKey] = $ResolvedResult
            return $ResolvedResult
        }
        catch {
        }

        try {
            $Group = Get-ADGroup -Identity $Result.SID -Properties GroupCategory, GroupScope, SID -ErrorAction Stop

            $Result.ObjectType        = 'Group'
            $Result.Name              = $Group.Name
            $Result.SamAccountName    = $Group.SamAccountName
            $Result.DistinguishedName = $Group.DistinguishedName
            $Result.DomainObject      = $true
            $Result.ResolutionStatus  = 'Resolved'

            $ResolvedResult = [pscustomobject]$Result
            $IdentityCache[$CacheKey] = $ResolvedResult
            return $ResolvedResult
        }
        catch {
        }
    }

    if ($IdentityReference -match '^(BUILTIN|NT AUTHORITY|CREATOR OWNER)$') {
        $Result.ObjectType = 'WellKnownPrincipal'
        $Result.ResolutionStatus = 'WellKnownPrincipal'
    }
    elseif ($IdentityReference -match '^(Everyone|Jeder)$') {
        $Result.ObjectType = 'WellKnownPrincipal'
        $Result.ResolutionStatus = 'WellKnownPrincipal'
    }
    elseif ($IdentityReference -match '\\') {
        $Result.ObjectType = 'LocalOrForeignPrincipal'
        $Result.ResolutionStatus = 'LocalOrForeignPrincipal'
    }

    $ResolvedResult = [pscustomobject]$Result
    $IdentityCache[$CacheKey] = $ResolvedResult

    if ($ResolvedResult.ResolutionStatus -eq 'Unresolved' -or $ResolvedResult.ResolutionStatus -eq 'LocalOrForeignPrincipal' -or $ResolvedResult.ResolutionStatus -eq 'WellKnownPrincipal') {
        Add-UnresolvedIdentity -Identity $IdentityReference -SID $Result.SID -Reason $Result.ResolutionStatus -Path $Path
    }

    return $ResolvedResult
}

function Expand-AdGroup {
    param(
        [Parameter(Mandatory)]
        [string]$GroupIdentity,

        [Parameter(Mandatory)]
        [string]$SourceGroup,

        [Parameter(Mandatory)]
        [string]$CurrentGroupPath,

        [hashtable]$VisitedGroups
    )

    if (-not $VisitedGroups) {
        $VisitedGroups = @{}
    }

    try {
        $Group = Get-ADGroup -Identity $GroupIdentity -Properties SID, GroupCategory, GroupScope -ErrorAction Stop
    }
    catch {
        Add-ScanError -Stage 'ResolveGroup' -Path $null -Identity $GroupIdentity -ErrorRecord $_
        return
    }

    $GroupSID = $Group.SID.Value

    if ($VisitedGroups.ContainsKey($GroupSID)) {
        $GroupStructure.Add([pscustomobject][ordered]@{
            SourceGroup             = $SourceGroup
            ParentGroup             = $Group.Name
            ParentGroupSID          = $GroupSID
            MemberType              = 'GroupCycle'
            MemberName              = $Group.Name
            MemberSamAccountName    = $Group.SamAccountName
            MemberUserPrincipalName = $null
            MemberSID               = $GroupSID
            MemberEnabled           = $null
            GroupPath               = $CurrentGroupPath
            IsExcluded              = $false
            Note                    = 'Circular group expansion detected'
        })
        return
    }

    $LocalVisited = @{}
    foreach ($Key in $VisitedGroups.Keys) {
        $LocalVisited[$Key] = $true
    }
    $LocalVisited[$GroupSID] = $true

    try {
        $Members = Get-ADGroupMember -Identity $Group.DistinguishedName -ErrorAction Stop
    }
    catch {
        Add-ScanError -Stage 'GetADGroupMember' -Path $null -Identity $Group.DistinguishedName -ErrorRecord $_
        return
    }

    foreach ($Member in $Members) {
        $MemberSID = $null

        try {
            if ($Member.SID) {
                $MemberSID = $Member.SID.Value
            }
        }
        catch {
        }

        switch ($Member.ObjectClass) {
            'user' {
                try {
                    $User = Get-ADUser -Identity $Member.DistinguishedName -Properties DisplayName, UserPrincipalName, Enabled, SID -ErrorAction Stop

                    $IsExcluded = Test-UserExcluded -SamAccountName $User.SamAccountName -UserPrincipalName $User.UserPrincipalName -SID $User.SID.Value

                    $GroupStructure.Add([pscustomobject][ordered]@{
                        SourceGroup             = $SourceGroup
                        ParentGroup             = $Group.Name
                        ParentGroupSID          = $GroupSID
                        MemberType              = 'User'
                        MemberName              = $User.Name
                        MemberSamAccountName    = $User.SamAccountName
                        MemberUserPrincipalName = $User.UserPrincipalName
                        MemberSID               = $User.SID.Value
                        MemberEnabled           = $User.Enabled
                        GroupPath               = $CurrentGroupPath
                        IsExcluded              = $IsExcluded
                        Note                    = $null
                    })
                }
                catch {
                    Add-ScanError -Stage 'ResolveGroupUser' -Path $null -Identity $Member.DistinguishedName -ErrorRecord $_
                }
            }

            'group' {
                $ChildPath = "$CurrentGroupPath -> $($Member.Name)"

                $GroupStructure.Add([pscustomobject][ordered]@{
                    SourceGroup             = $SourceGroup
                    ParentGroup             = $Group.Name
                    ParentGroupSID          = $GroupSID
                    MemberType              = 'Group'
                    MemberName              = $Member.Name
                    MemberSamAccountName    = $Member.SamAccountName
                    MemberUserPrincipalName = $null
                    MemberSID               = $MemberSID
                    MemberEnabled           = $null
                    GroupPath               = $ChildPath
                    IsExcluded              = $false
                    Note                    = $null
                })

                Expand-AdGroup -GroupIdentity $Member.DistinguishedName -SourceGroup $SourceGroup -CurrentGroupPath $ChildPath -VisitedGroups $LocalVisited
            }

            'computer' {
                $GroupStructure.Add([pscustomobject][ordered]@{
                    SourceGroup             = $SourceGroup
                    ParentGroup             = $Group.Name
                    ParentGroupSID          = $GroupSID
                    MemberType              = 'Computer'
                    MemberName              = $Member.Name
                    MemberSamAccountName    = $Member.SamAccountName
                    MemberUserPrincipalName = $null
                    MemberSID               = $MemberSID
                    MemberEnabled           = $null
                    GroupPath               = $CurrentGroupPath
                    IsExcluded              = $false
                    Note                    = 'Computer object is not evaluated as user access'
                })
            }

            default {
                $GroupStructure.Add([pscustomobject][ordered]@{
                    SourceGroup             = $SourceGroup
                    ParentGroup             = $Group.Name
                    ParentGroupSID          = $GroupSID
                    MemberType              = $Member.ObjectClass
                    MemberName              = $Member.Name
                    MemberSamAccountName    = $Member.SamAccountName
                    MemberUserPrincipalName = $null
                    MemberSID               = $MemberSID
                    MemberEnabled           = $null
                    GroupPath               = $CurrentGroupPath
                    IsExcluded              = $false
                    Note                    = 'Unsupported AD object type'
                })
            }
        }
    }
}

function Get-ExpandedGroupUsers {
    param(
        [Parameter(Mandatory)]
        [string]$GroupSID,

        [Parameter(Mandatory)]
        [string]$GroupName
    )

    if ($GroupExpansionCache.ContainsKey($GroupSID)) {
        return $GroupExpansionCache[$GroupSID]
    }

    $BeforeCount = $GroupStructure.Count

    Expand-AdGroup -GroupIdentity $GroupSID -SourceGroup $GroupName -CurrentGroupPath $GroupName -VisitedGroups @{}

    $NewRows = @()

    if ($GroupStructure.Count -gt $BeforeCount) {
        $NewRows = @($GroupStructure[$BeforeCount..($GroupStructure.Count - 1)])
    }

    $Users = @(
        $NewRows |
            Where-Object { $_.MemberType -eq 'User' } |
            Select-Object MemberName, MemberSamAccountName, MemberUserPrincipalName, MemberSID, MemberEnabled, GroupPath, IsExcluded -Unique
    )

    $GroupExpansionCache[$GroupSID] = $Users
    return $Users
}

function Add-UserAccessRow {
    param(
        [Parameter(Mandatory)]
        [object]$AclRow,

        [Parameter(Mandatory)]
        [string]$UserName,

        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [string]$UserPrincipalName,

        [Parameter(Mandatory)]
        [string]$UserSID,

        [Nullable[bool]]$Enabled,

        [Parameter(Mandatory)]
        [string]$AssignmentType,

        [string]$PermissionSource,

        [string]$PermissionSourceSID,

        [string]$GroupPath
    )

    $IsExcluded = Test-UserExcluded -SamAccountName $SamAccountName -UserPrincipalName $UserPrincipalName -SID $UserSID

    if ($IsExcluded) {
        return
    }

    if ($ExcludeDisabledUsers -and $Enabled -eq $false) {
        return
    }

    $UserAccess.Add([pscustomobject][ordered]@{
        ItemPath            = $AclRow.ItemPath
        ItemType            = $AclRow.ItemType
        UserName            = $UserName
        SamAccountName      = $SamAccountName
        UserPrincipalName   = $UserPrincipalName
        UserSID             = $UserSID
        UserEnabled         = $Enabled
        AssignmentType      = $AssignmentType
        PermissionSource    = $PermissionSource
        PermissionSourceSID = $PermissionSourceSID
        GroupPath           = $GroupPath
        AccessControlType   = $AclRow.AccessControlType
        FileSystemRights    = $AclRow.FileSystemRights
        RightsMask          = $AclRow.RightsMask
        IsInherited         = $AclRow.IsInherited
        InheritanceFlags    = $AclRow.InheritanceFlags
        PropagationFlags    = $AclRow.PropagationFlags
        Owner               = $AclRow.Owner
    })
}

function Process-FileSystemItem {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [string]$ItemType,

        [switch]$IsRoot
    )

    try {
        $Acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop
    }
    catch {
        Add-ScanError -Stage 'GetAcl' -Path $Item.FullName -Identity $null -ErrorRecord $_
        return
    }

    $ExplicitAccessRules = @(
        $Acl.Access | Where-Object { -not $_.IsInherited }
    )

    $InheritanceProtected = [bool]$Acl.AreAccessRulesProtected
    $HasExplicitAccessRules = $ExplicitAccessRules.Count -gt 0

    $IsPermissionBoundary = (
        $IsRoot.IsPresent -or
        $InheritanceProtected -or
        $HasExplicitAccessRules
    )

    if ($OnlyPermissionBoundaries.IsPresent -and -not $IsPermissionBoundary) {
        $script:InheritedOnlySkippedCount++
        return
    }

    if ($IsPermissionBoundary) {
        $script:PermissionBoundaryCount++
    }

    if ($InheritanceProtected) {
        $script:ProtectedAclCount++
    }

    if ($HasExplicitAccessRules) {
        $script:ExplicitAclCount++
    }

    if ($IsPermissionBoundary) {
        $AccessRulesToProcess = @($Acl.Access)
    }
    else {
        $AccessRulesToProcess = @()
    }

    foreach ($AccessRule in $AccessRulesToProcess) {
        $IdentityName = $AccessRule.IdentityReference.Value

        if ($ExcludedAclGroups -contains $IdentityName) {
            continue
        }

        $ResolvedIdentity = Resolve-AclIdentity -IdentityReference $IdentityName -Path $Item.FullName
        $RightsMask = Get-RightsMask -Rights $AccessRule.FileSystemRights

        $AclRow = [pscustomobject][ordered]@{
            ItemPath          = $Item.FullName
            ItemType          = $ItemType
            Owner             = $Acl.Owner
            IdentityReference = $IdentityName
            ResolvedName      = $ResolvedIdentity.Name
            ResolvedType      = $ResolvedIdentity.ObjectType
            IdentitySID       = $ResolvedIdentity.SID
            ResolutionStatus  = $ResolvedIdentity.ResolutionStatus
            AccessControlType = $AccessRule.AccessControlType.ToString()
            FileSystemRights  = $AccessRule.FileSystemRights.ToString()
            RightsMask        = $RightsMask
            IsInherited       = $AccessRule.IsInherited
            InheritanceFlags  = $AccessRule.InheritanceFlags.ToString()
            PropagationFlags  = $AccessRule.PropagationFlags.ToString()
            Sddl              = $Acl.Sddl
        }

        $AclRaw.Add($AclRow)

        switch ($ResolvedIdentity.ObjectType) {
            'User' {
                Add-UserAccessRow -AclRow $AclRow -UserName $ResolvedIdentity.Name -SamAccountName $ResolvedIdentity.SamAccountName -UserPrincipalName $ResolvedIdentity.UserPrincipalName -UserSID $ResolvedIdentity.SID -Enabled $ResolvedIdentity.Enabled -AssignmentType 'Direct' -PermissionSource $ResolvedIdentity.Name -PermissionSourceSID $ResolvedIdentity.SID
            }

            'Group' {
                $GroupUsers = Get-ExpandedGroupUsers -GroupSID $ResolvedIdentity.SID -GroupName $ResolvedIdentity.Name

                foreach ($GroupUser in $GroupUsers) {
                    Add-UserAccessRow -AclRow $AclRow -UserName $GroupUser.MemberName -SamAccountName $GroupUser.MemberSamAccountName -UserPrincipalName $GroupUser.MemberUserPrincipalName -UserSID $GroupUser.MemberSID -Enabled $GroupUser.MemberEnabled -AssignmentType 'GroupMember' -PermissionSource $ResolvedIdentity.Name -PermissionSourceSID $ResolvedIdentity.SID -GroupPath $GroupUser.GroupPath
                }
            }

            default {
                # Well-known, local, and unresolved identities are tracked in the raw report and unresolved report.
            }
        }
    }
}

function Get-FileSha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $FileBytes = [System.IO.File]::ReadAllBytes($Path)
    $Hash = [System.Security.Cryptography.SHA256]::Create()
    $HashBytes = $Hash.ComputeHash($FileBytes)
    $Builder = [System.Text.StringBuilder]::new()

    foreach ($Byte in $HashBytes) {
        [void]$Builder.Append($Byte.ToString('x2'))
    }

    return $Builder.ToString()
}

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

Write-Log 'Starting file permission audit.'
Write-Log "RootPath: $RootPath"
Write-Log "OutputPath: $OutputPath"
Write-Log "IncludeFiles: $IncludeFiles"
Write-Log "Executing user: $ExecutingUser"

if (-not (Test-Path -LiteralPath $RootPath)) {
    throw "The specified RootPath is not reachable: $RootPath"
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

Initialize-ExcludedUsers

# ------------------------------------------------------------
# Process root item
# ------------------------------------------------------------

try {
    $RootItem = Get-Item -LiteralPath $RootPath -Force -ErrorAction Stop
    Process-FileSystemItem -Item $RootItem -ItemType 'Directory' -IsRoot
}
catch {
    Write-Host ''
    Write-Host '===== ORIGINAL ERROR =====' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ''
    Write-Host $_.ScriptStackTrace -ForegroundColor Cyan
    Write-Host ''

    Add-ScanError -Stage 'GetRootItem' -Path $RootPath -Identity $null -ErrorRecord $_

    throw
}

# ------------------------------------------------------------
# Process directories
# ------------------------------------------------------------

Write-Log 'Resolving subdirectories.'

try {
    $Directories = @(
        Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable DirectoryEnumerationErrors
    )

    foreach ($EnumerationError in $DirectoryEnumerationErrors) {
        Add-ScanError -Stage 'EnumerateDirectory' -Path $EnumerationError.TargetObject -Identity $null -ErrorRecord $EnumerationError
    }
}
catch {
    Add-ScanError -Stage 'EnumerateDirectories' -Path $RootPath -Identity $null -ErrorRecord $_
    $Directories = @()
}

$DirectoryNumber = 0
foreach ($Directory in $Directories) {
    $DirectoryNumber++

    if (($DirectoryNumber % 250) -eq 0) {
        Write-Log "$DirectoryNumber of $($Directories.Count) directories processed."
    }

    Process-FileSystemItem -Item $Directory -ItemType 'Directory'
}

# ------------------------------------------------------------
# Optional file processing
# ------------------------------------------------------------

$Files = @()

if ($IncludeFiles) {
    Write-Log 'Resolving files. This can take a long time on large file servers.'

    try {
        $Files = @(
            Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable FileEnumerationErrors
        )

        foreach ($EnumerationError in $FileEnumerationErrors) {
            Add-ScanError -Stage 'EnumerateFile' -Path $EnumerationError.TargetObject -Identity $null -ErrorRecord $EnumerationError
        }
    }
    catch {
        Add-ScanError -Stage 'EnumerateFiles' -Path $RootPath -Identity $null -ErrorRecord $_
        $Files = @()
    }

    $FileNumber = 0
    foreach ($File in $Files) {
        $FileNumber++

        if (($FileNumber % 1000) -eq 0) {
            Write-Log "$FileNumber of $($Files.Count) files processed."
        }

        Process-FileSystemItem -Item $File -ItemType 'File'
    }
}

# ------------------------------------------------------------
# Consolidated user permissions
# ------------------------------------------------------------

Write-Log 'Creating consolidated user overview.'

$UserEffectiveSummary = [System.Collections.Generic.List[object]]::new()

$GroupedUserAccess = $UserAccess | Group-Object -Property UserSID, ItemPath

foreach ($AccessGroup in $GroupedUserAccess) {
    $Rows = @($AccessGroup.Group)

    if ($Rows.Count -eq 0) {
        continue
    }

    [uint32]$AllowMask = 0
    [uint32]$DenyMask = 0

    foreach ($Row in $Rows) {
        [uint32]$CurrentMask = [uint32]$Row.RightsMask

        if ($Row.AccessControlType -eq 'Allow') {
            $AllowMask = $AllowMask -bor $CurrentMask
        }
        elseif ($Row.AccessControlType -eq 'Deny') {
            $DenyMask = $DenyMask -bor $CurrentMask
        }
    }

    [uint32]$DerivedMask = $AllowMask -band (-bnot $DenyMask)

    $PermissionSources = @(
        $Rows |
            ForEach-Object {
                if ($_.AssignmentType -eq 'Direct') {
                    'Direct:' + $_.PermissionSource
                }
                elseif ($_.GroupPath) {
                    'Group:' + $_.GroupPath
                }
                else {
                    'Group:' + $_.PermissionSource
                }
            } |
            Sort-Object -Unique
    ) -join ' | '

    $UserEffectiveSummary.Add([pscustomobject][ordered]@{
        ItemPath          = $Rows[0].ItemPath
        ItemType          = $Rows[0].ItemType
        UserName          = $Rows[0].UserName
        SamAccountName    = $Rows[0].SamAccountName
        UserPrincipalName = $Rows[0].UserPrincipalName
        UserSID           = $Rows[0].UserSID
        UserEnabled       = $Rows[0].UserEnabled
        AllowRights       = Convert-RightsMaskToText -Mask $AllowMask
        AllowMask         = $AllowMask
        DenyRights        = Convert-RightsMaskToText -Mask $DenyMask
        DenyMask          = $DenyMask
        DerivedRights     = Convert-RightsMaskToText -Mask $DerivedMask
        DerivedRightsMask = $DerivedMask
        PermissionSources = $PermissionSources
        AssignmentCount   = $Rows.Count
        EvaluationNote     = 'Technical NTFS ACL derivation; not a full Windows user token evaluation'
    })
}

# ------------------------------------------------------------
# Export
# ------------------------------------------------------------

Write-Log 'Exporting results.'

$OutputFiles = [ordered]@{
    AclRaw               = Join-Path $OutputPath '01_ACL_Raw.csv'
    GroupStructure       = Join-Path $OutputPath '02_GroupStructure.csv'
    UserAccess           = Join-Path $OutputPath '03_UserAccess.csv'
    UserEffectiveSummary = Join-Path $OutputPath '04_UserEffectiveSummary.csv'
    UnresolvedIdentities = Join-Path $OutputPath '05_UnresolvedIdentities.csv'
    ScanErrors           = Join-Path $OutputPath '06_ScanErrors.csv'
    Manifest             = Join-Path $OutputPath 'AuditManifest.json'
}

$AclRaw |
    Sort-Object ItemPath, IdentityReference, AccessControlType |
    Export-Csv -LiteralPath $OutputFiles.AclRaw -Delimiter $CsvDelimiter -NoTypeInformation -Encoding UTF8

$GroupStructure |
    Sort-Object SourceGroup, GroupPath, MemberType, MemberSamAccountName |
    Export-Csv -LiteralPath $OutputFiles.GroupStructure -Delimiter $CsvDelimiter -NoTypeInformation -Encoding UTF8

$UserAccess |
    Sort-Object SamAccountName, ItemPath, AccessControlType, PermissionSource |
    Export-Csv -LiteralPath $OutputFiles.UserAccess -Delimiter $CsvDelimiter -NoTypeInformation -Encoding UTF8

$UserEffectiveSummary |
    Sort-Object ItemPath, UserName |
    Export-Csv -LiteralPath $OutputFiles.UserEffectiveSummary -Delimiter $CsvDelimiter -NoTypeInformation -Encoding UTF8

$UnresolvedIdentities |
    Sort-Object Identity, Path |
    Export-Csv -LiteralPath $OutputFiles.UnresolvedIdentities -Delimiter $CsvDelimiter -NoTypeInformation -Encoding UTF8

$ScanErrors |
    Sort-Object Timestamp, Stage, Path |
    Export-Csv -LiteralPath $OutputFiles.ScanErrors -Delimiter $CsvDelimiter -NoTypeInformation -Encoding UTF8

$ManifestData = [ordered]@{
    RunId               = $RunId
    GeneratedAtUtc      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    GeneratedAtLocal    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    RootPath            = $RootPath
    OutputPath          = $OutputPath
    ComputerName        = $ComputerName
    ExecutingUser       = $ExecutingUser
    IncludeFiles        = $IncludeFiles.IsPresent
    ExcludeDisabledUsers = $ExcludeDisabledUsers.IsPresent
    CsvDelimiter        = $CsvDelimiter
    Files = [ordered]@{
        AclRaw               = Get-FileSha256 -Path $OutputFiles.AclRaw
        GroupStructure       = Get-FileSha256 -Path $OutputFiles.GroupStructure
        UserAccess           = Get-FileSha256 -Path $OutputFiles.UserAccess
        UserEffectiveSummary = Get-FileSha256 -Path $OutputFiles.UserEffectiveSummary
        UnresolvedIdentities = Get-FileSha256 -Path $OutputFiles.UnresolvedIdentities
        ScanErrors           = Get-FileSha256 -Path $OutputFiles.ScanErrors
    }
    Counts = [ordered]@{
        AclRawCount              = $AclRaw.Count
        GroupStructureCount      = $GroupStructure.Count
        UserAccessCount          = $UserAccess.Count
        SummaryCount             = $UserEffectiveSummary.Count
        UnresolvedCount          = $UnresolvedIdentities.Count
        ScanErrorsCount          = $ScanErrors.Count
        PermissionBoundaryCount  = $PermissionBoundaryCount
        InheritedOnlySkippedCount = $InheritedOnlySkippedCount
        ProtectedAclCount        = $ProtectedAclCount
        ExplicitAclCount         = $ExplicitAclCount
    }
}

$ManifestData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputFiles.Manifest -Encoding UTF8

Write-Log "Audit completed. Results written to $OutputPath"
Write-Log "Summary count: $($UserEffectiveSummary.Count)"
Write-Log "Unresolved identities: $($UnresolvedIdentities.Count)"
Write-Log "Scan errors: $($ScanErrors.Count)"
