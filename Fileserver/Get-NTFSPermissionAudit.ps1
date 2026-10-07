#requires -Version 5.1
#requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Revisionsorientierte Auswertung von NTFS-Berechtigungen.

.DESCRIPTION
    Das Skript erfasst:
    - NTFS-ACLs von Ordnern und optional Dateien
    - direkte Benutzerberechtigungen
    - AD-Berechtigungsgruppen
    - verschachtelte Gruppen
    - Benutzer innerhalb verschachtelter Gruppen
    - Herkunft jeder Benutzerberechtigung
    - Allow- und Deny-Einträge
    - nicht auflösbare Identitäten
    - Fehler während des Scans
    - SHA-256-Prüfsummen der erzeugten Berichte

.NOTES
    Das Skript ermittelt NTFS-Berechtigungen.

    Nicht automatisch berücksichtigt werden:
    - SMB-Share-Berechtigungen
    - Dynamic Access Control
    - Central Access Policies
    - Benutzerrechte wie Backup Operators
    - Access Based Enumeration
    - Berechtigungen über SIDHistory in jedem Sonderfall
    - lokale Gruppen auf entfernten Fileservern
    - zum Zeitpunkt der Anmeldung vorhandene Kerberos-Tokens
    - Applikationsberechtigungen oberhalb des Dateisystems

    Die Spalte DerivedRights stellt eine nachvollziehbare technische
    ACL-Ableitung dar, ersetzt aber nicht die Windows-Funktion
    "Effektiver Zugriff" für einen konkreten Benutzer-Token.
#>

[CmdletBinding()]
param(
    # Besser einen UNC-Pfad verwenden, zum Beispiel:
    # \\server\share oder \\server\share\Data
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RootPath = "V:\",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "C:\Temp\WVAG_Berechtigungspruefung_2026",

    # Standardmäßig werden nur Ordner geprüft.
    # Mit diesem Schalter werden zusätzlich alle Dateien ausgewertet.
    [Parameter(Mandatory = $false)]
    [switch]$IncludeFiles,

    # Optional: CSV mit auszuschließenden Benutzern.
    # Unterstützte Spalten:
    # SamAccountName, UserPrincipalName oder SID
    [Parameter(Mandatory = $false)]
    [string]$ExcludedUsersCsv,

    # Standardmäßig deaktivierte Benutzer nicht in UserAccess aufnehmen.
    [Parameter(Mandatory = $false)]
    [switch]$ExcludeDisabledUsers,

    # CSV-Trennzeichen
    [Parameter(Mandatory = $false)]
    [char]$CsvDelimiter = ';'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory -ErrorAction Stop

# ------------------------------------------------------------
# Initialisierung
# ------------------------------------------------------------

$ScriptStart = Get-Date
$RunId = $ScriptStart.ToString("yyyyMMdd_HHmmss")
$ComputerName = $env:COMPUTERNAME
$ExecutingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$AclRaw                = [System.Collections.Generic.List[object]]::new()
$GroupStructure        = [System.Collections.Generic.List[object]]::new()
$UserAccess            = [System.Collections.Generic.List[object]]::new()
$UnresolvedIdentities  = [System.Collections.Generic.List[object]]::new()
$ScanErrors            = [System.Collections.Generic.List[object]]::new()

$IdentityCache = @{}
$GroupExpansionCache = @{}
$ExcludedUsers = @{}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$TimeStamp][$Level] $Message"
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $InvalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()

    foreach ($Character in $InvalidCharacters) {
        $Name = $Name.Replace($Character, "_")
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
        return "None"
    }

    try {
        return ([System.Security.AccessControl.FileSystemRights]$Mask).ToString()
    }
    catch {
        return ("0x{0:X8}" -f $Mask)
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
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Stage          = $Stage
        Path           = $Path
        Identity       = $Identity
        ErrorMessage   = $ErrorRecord.Exception.Message
        ExceptionType  = $ErrorRecord.Exception.GetType().FullName
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
    if (:IsNullOrWhiteSpace($ExcludedUsersCsv)) {
        return
    }

    if (-not (Test-Path -LiteralPath $ExcludedUsersCsv)) {
        throw "Die Ausschlussdatei wurde nicht gefunden: $ExcludedUsersCsv"
    }

    Write-Log "Lese auszuschließende Benutzer aus $ExcludedUsersCsv"

    $Entries = Import-Csv -LiteralPath $ExcludedUsersCsv -Delimiter $CsvDelimiter

    foreach ($Entry in $Entries) {
        foreach ($PropertyName in @("SamAccountName", "UserPrincipalName", "SID")) {
            if (
                $Entry.PSObject.Properties.Name -contains $PropertyName -and
                -not :IsNullOrWhiteSpace($Entry.$PropertyName)
            ) {
                $ExcludedUsers[$Entry.$PropertyName.Trim().ToLowerInvariant()] = $true
            }
        }
    }

    Write-Log "$($ExcludedUsers.Count) Ausschlusswerte wurden eingelesen."
}

function Test-UserExcluded {
    param(
        [string]$SamAccountName,
        [string]$UserPrincipalName,
        [string]$SID
    )

    foreach ($Value in @($SamAccountName, $UserPrincipalName, $SID)) {
        if (
            -not :IsNullOrWhiteSpace($Value) -and
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

    $CacheKey = $IdentityReference.ToLowerInvariant()

    if ($IdentityCache.ContainsKey($CacheKey)) {
        return $IdentityCache[$CacheKey]
    }

    $Result = [ordered]@{
        OriginalIdentity  = $IdentityReference
        SID               = $null
        ObjectType        = "Unknown"
        Name              = $IdentityReference
        SamAccountName    = $null
        UserPrincipalName = $null
        DistinguishedName = $null
        Enabled           = $null
        DomainObject      = $false
        ResolutionStatus  = "Unresolved"
    }

    try {
        $NTAccount = [System.Security.Principal.NTAccount]::new($IdentityReference)
        $SIDObject = $NTAccount.Translate(
            [System.Security.Principal.SecurityIdentifier]
        )

        $Result.SID = $SIDObject.Value
    }
    catch {
        if ($IdentityReference -match "^S-\d-\d+-.+") {
            $Result.SID = $IdentityReference
        }
    }

    if ($Result.SID) {
        try {
            $User = Get-ADUser `
                -Identity $Result.SID `
                -Properties DisplayName, UserPrincipalName, Enabled, SID `
                -ErrorAction Stop

            $Result.ObjectType        = "User"
            $Result.Name              = $User.Name
            $Result.SamAccountName    = $User.SamAccountName
            $Result.UserPrincipalName = $User.UserPrincipalName
            $Result.DistinguishedName = $User.DistinguishedName
            $Result.Enabled           = $User.Enabled
            $Result.DomainObject      = $true
            $Result.ResolutionStatus  = "Resolved"

            $ResolvedResult = [pscustomobject]$Result
            $IdentityCache[$CacheKey] = $ResolvedResult
            return $ResolvedResult
        }
        catch {
        }

        try {
            $Group = Get-ADGroup `
                -Identity $Result.SID `
                -Properties GroupCategory, GroupScope, SID `
                -ErrorAction Stop

            $Result.ObjectType        = "Group"
            $Result.Name              = $Group.Name
            $Result.SamAccountName    = $Group.SamAccountName
            $Result.DistinguishedName = $Group.DistinguishedName
            $Result.DomainObject      = $true
            $Result.ResolutionStatus  = "Resolved"

            $ResolvedResult = [pscustomobject]$Result
            $IdentityCache[$CacheKey] = $ResolvedResult
            return $ResolvedResult
        }
        catch {
        }
    }

    switch -Regex ($IdentityReference) {
        "^(BUILTIN\\|NT AUTHORITY\\|CREATOR OWNER$)" {
            $Result.ObjectType = "WellKnownPrincipal"
            $Result.ResolutionStatus = "WellKnownPrincipal"
        }

        "Everyone$|Jeder$" {
            $Result.ObjectType = "WellKnownPrincipal"
            $Result.ResolutionStatus = "WellKnownPrincipal"
        }

        default {
            if ($IdentityReference -match "\\") {
                $Result.ObjectType = "LocalOrForeignPrincipal"
                $Result.ResolutionStatus = "LocalOrForeignPrincipal"
            }
        }
    }

    $ResolvedResult = [pscustomobject]$Result
    $IdentityCache[$CacheKey] = $ResolvedResult

    Add-UnresolvedIdentity `
        -Identity $IdentityReference `
        -SID $Result.SID `
        -Reason $Result.ResolutionStatus `
        -Path $Path

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
        $Group = Get-ADGroup `
            -Identity $GroupIdentity `
            -Properties SID, GroupCategory, GroupScope `
            -ErrorAction Stop
    }
    catch {
        Add-ScanError `
            -Stage "ResolveGroup" `
            -Path $null `
            -Identity $GroupIdentity `
            -ErrorRecord $_

        return
    }

    $GroupSID = $Group.SID.Value

    if ($VisitedGroups.ContainsKey($GroupSID)) {
        $GroupStructure.Add([pscustomobject][ordered]@{
            SourceGroup             = $SourceGroup
            ParentGroup             = $Group.Name
            ParentGroupSID          = $GroupSID
            MemberType              = "GroupCycle"
            MemberName              = $Group.Name
            MemberSamAccountName    = $Group.SamAccountName
            MemberUserPrincipalName = $null
            MemberSID               = $GroupSID
            MemberEnabled           = $null
            GroupPath               = $CurrentGroupPath
            IsExcluded              = $false
            Note                    = "Zirkuläre Gruppenverschachtelung erkannt"
        })

        return
    }

    $LocalVisited = @{}

    foreach ($Key in $VisitedGroups.Keys) {
        $LocalVisited[$Key] = $true
    }

    $LocalVisited[$GroupSID] = $true

    try {
        $Members = Get-ADGroupMember `
            -Identity $Group.DistinguishedName `
            -ErrorAction Stop
    }
    catch {
        Add-ScanError `
            -Stage "GetADGroupMember" `
            -Path $null `
            -Identity $Group.DistinguishedName `
            -ErrorRecord $_

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
            "user" {
                try {
                    $User = Get-ADUser `
                        -Identity $Member.DistinguishedName `
                        -Properties DisplayName, UserPrincipalName, Enabled, SID `
                        -ErrorAction Stop

                    $IsExcluded = Test-UserExcluded `
                        -SamAccountName $User.SamAccountName `
                        -UserPrincipalName $User.UserPrincipalName `
                        -SID $User.SID.Value

                    $GroupStructure.Add([pscustomobject][ordered]@{
                        SourceGroup             = $SourceGroup
                        ParentGroup             = $Group.Name
                        ParentGroupSID          = $GroupSID
                        MemberType              = "User"
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
                    Add-ScanError `
                        -Stage "ResolveGroupUser" `
                        -Path $null `
                        -Identity $Member.DistinguishedName `
                        -ErrorRecord $_
                }
            }

            "group" {
                $ChildPath = "$CurrentGroupPath -> $($Member.Name)"

                $GroupStructure.Add([pscustomobject][ordered]@{
                    SourceGroup             = $SourceGroup
                    ParentGroup             = $Group.Name
                    ParentGroupSID          = $GroupSID
                    MemberType              = "Group"
                    MemberName              = $Member.Name
                    MemberSamAccountName    = $Member.SamAccountName
                    MemberUserPrincipalName = $null
                    MemberSID               = $MemberSID
                    MemberEnabled           = $null
                    GroupPath               = $ChildPath
                    IsExcluded              = $false
                    Note                    = $null
                })

                Expand-AdGroup `
                    -GroupIdentity $Member.DistinguishedName `
                    -SourceGroup $SourceGroup `
                    -CurrentGroupPath $ChildPath `
                    -VisitedGroups $LocalVisited
            }

            "computer" {
                $GroupStructure.Add([pscustomobject][ordered]@{
                    SourceGroup             = $SourceGroup
                    ParentGroup             = $Group.Name
                    ParentGroupSID          = $GroupSID
                    MemberType              = "Computer"
                    MemberName              = $Member.Name
                    MemberSamAccountName    = $Member.SamAccountName
                    MemberUserPrincipalName = $null
                    MemberSID               = $MemberSID
                    MemberEnabled           = $null
                    GroupPath               = $CurrentGroupPath
                    IsExcluded              = $false
                    Note                    = "Computerobjekt wird nicht als Benutzerzugriff ausgewertet"
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
                    Note                    = "Nicht unterstützter AD-Objekttyp"
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

    Expand-AdGroup `
        -GroupIdentity $GroupSID `
        -SourceGroup $GroupName `
        -CurrentGroupPath $GroupName `
        -VisitedGroups @{}

    $NewRows = @()

    if ($GroupStructure.Count -gt $BeforeCount) {
        $NewRows = @(
            $GroupStructure[$BeforeCount..($GroupStructure.Count - 1)]
        )
    }

    $Users = @(
        $NewRows |
            Where-Object {
                $_.MemberType -eq "User"
            } |
            Select-Object `
                MemberName,
                MemberSamAccountName,
                MemberUserPrincipalName,
                MemberSID,
                MemberEnabled,
                GroupPath,
                IsExcluded `
                -Unique
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

    $IsExcluded = Test-UserExcluded `
        -SamAccountName $SamAccountName `
        -UserPrincipalName $UserPrincipalName `
        -SID $UserSID

    if ($IsExcluded) {
        return
    }

    if ($ExcludeDisabledUsers -and $Enabled -eq $false) {
        return
    }

    $UserAccess.Add([pscustomobject][ordered]@{
        ItemPath             = $AclRow.ItemPath
        ItemType             = $AclRow.ItemType
        UserName             = $UserName
        SamAccountName       = $SamAccountName
        UserPrincipalName    = $UserPrincipalName
        UserSID              = $UserSID
        UserEnabled          = $Enabled
        AssignmentType       = $AssignmentType
        PermissionSource     = $PermissionSource
        PermissionSourceSID  = $PermissionSourceSID
        GroupPath            = $GroupPath
        AccessControlType    = $AclRow.AccessControlType
        FileSystemRights     = $AclRow.FileSystemRights
        RightsMask           = $AclRow.RightsMask
        IsInherited          = $AclRow.IsInherited
        InheritanceFlags     = $AclRow.InheritanceFlags
        PropagationFlags     = $AclRow.PropagationFlags
        Owner                = $AclRow.Owner
    })
}

function Process-FileSystemItem {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [string]$ItemType
    )

    try {
        $Acl = Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop
    }
    catch {
        Add-ScanError `
            -Stage "GetAcl" `
            -Path $Item.FullName `
            -Identity $null `
            -ErrorRecord $_

        return
    }

    foreach ($AccessRule in $Acl.Access) {
        $IdentityName = $AccessRule.IdentityReference.Value
        $ResolvedIdentity = Resolve-AclIdentity `
            -IdentityReference $IdentityName `
            -Path $Item.FullName

        $RightsMask = Get-RightsMask -Rights $AccessRule.FileSystemRights

        $AclRow = [pscustomobject][ordered]@{
            ItemPath           = $Item.FullName
            ItemType           = $ItemType
            Owner              = $Acl.Owner
            IdentityReference  = $IdentityName
            ResolvedName       = $ResolvedIdentity.Name
            ResolvedType       = $ResolvedIdentity.ObjectType
            IdentitySID        = $ResolvedIdentity.SID
            ResolutionStatus   = $ResolvedIdentity.ResolutionStatus
            AccessControlType  = $AccessRule.AccessControlType.ToString()
            FileSystemRights   = $AccessRule.FileSystemRights.ToString()
            RightsMask         = $RightsMask
            IsInherited        = $AccessRule.IsInherited
            InheritanceFlags   = $AccessRule.InheritanceFlags.ToString()
            PropagationFlags   = $AccessRule.PropagationFlags.ToString()
            Sddl               = $Acl.Sddl
        }

        $AclRaw.Add($AclRow)

        switch ($ResolvedIdentity.ObjectType) {
            "User" {
                Add-UserAccessRow `
                    -AclRow $AclRow `
                    -UserName $ResolvedIdentity.Name `
                    -SamAccountName $ResolvedIdentity.SamAccountName `
                    -UserPrincipalName $ResolvedIdentity.UserPrincipalName `
                    -UserSID $ResolvedIdentity.SID `
                    -Enabled $ResolvedIdentity.Enabled `
                    -AssignmentType "Direct" `
                    -PermissionSource $IdentityName `
                    -PermissionSourceSID $ResolvedIdentity.SID `
                    -GroupPath $null
            }

            "Group" {
                $GroupUsers = Get-ExpandedGroupUsers `
                    -GroupSID $ResolvedIdentity.SID `
                    -GroupName $ResolvedIdentity.Name

                foreach ($GroupUser in $GroupUsers) {
                    Add-UserAccessRow `
                        -AclRow $AclRow `
                        -UserName $GroupUser.MemberName `
                        -SamAccountName $GroupUser.MemberSamAccountName `
                        -UserPrincipalName $GroupUser.MemberUserPrincipalName `
                        -UserSID $GroupUser.MemberSID `
                        -Enabled $GroupUser.MemberEnabled `
                        -AssignmentType "Group" `
                        -PermissionSource $ResolvedIdentity.Name `
                        -PermissionSourceSID $ResolvedIdentity.SID `
                        -GroupPath $GroupUser.GroupPath
                }
            }

            default {
                # Well-known, lokale und nicht auflösbare Identitäten
                # werden im Rohbericht und im Bericht für nicht
                # auflösbare Identitäten dokumentiert.
            }
        }
    }
}

# ------------------------------------------------------------
# Validierung
# ------------------------------------------------------------

Write-Log "Starte Berechtigungsprüfung."
Write-Log "RootPath: $RootPath"
Write-Log "OutputPath: $OutputPath"
Write-Log "IncludeFiles: $IncludeFiles"
Write-Log "Ausführender Benutzer: $ExecutingUser"

if (-not (Test-Path -LiteralPath $RootPath)) {
    throw "Der angegebene RootPath ist nicht erreichbar: $RootPath"
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item `
        -Path $OutputPath `
        -ItemType Directory `
        -Force | Out-Null
}

Initialize-ExcludedUsers

# ------------------------------------------------------------
# Root-Objekt verarbeiten
# ------------------------------------------------------------

try {
    $RootItem = Get-Item -LiteralPath $RootPath -Force -ErrorAction Stop
    Process-FileSystemItem -Item $RootItem -ItemType "Directory"
}
catch {
    Add-ScanError `
        -Stage "GetRootItem" `
        -Path $RootPath `
        -Identity $null `
        -ErrorRecord $_

    throw "Das Root-Verzeichnis konnte nicht ausgewertet werden: $RootPath"
}

# ------------------------------------------------------------
# Verzeichnisse verarbeiten
# ------------------------------------------------------------

Write-Log "Ermittle Unterverzeichnisse."

try {
    $Directories = @(
        Get-ChildItem `
            -LiteralPath $RootPath `
            -Directory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue `
            -ErrorVariable DirectoryEnumerationErrors
    )

    foreach ($EnumerationError in $DirectoryEnumerationErrors) {
        Add-ScanError `
            -Stage "EnumerateDirectory" `
            -Path $EnumerationError.TargetObject `
            -Identity $null `
            -ErrorRecord $EnumerationError
    }
}
catch {
    Add-ScanError `
        -Stage "EnumerateDirectories" `
        -Path $RootPath `
        -Identity $null `
        -ErrorRecord $_

    $Directories = @()
}

$DirectoryNumber = 0

foreach ($Directory in $Directories) {
    $DirectoryNumber++

    if (($DirectoryNumber % 250) -eq 0) {
        Write-Log "$DirectoryNumber von $($Directories.Count) Verzeichnissen verarbeitet."
    }

    Process-FileSystemItem `
        -Item $Directory `
        -ItemType "Directory"
}

# ------------------------------------------------------------
# Optional Dateien verarbeiten
# ------------------------------------------------------------

$Files = @()

if ($IncludeFiles) {
    Write-Log "Ermittle Dateien. Dies kann bei großen Datenbeständen umfangreich sein."

    try {
        $Files = @(
            Get-ChildItem `
                -LiteralPath $RootPath `
                -File `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue `
                -ErrorVariable FileEnumerationErrors
        )

        foreach ($EnumerationError in $FileEnumerationErrors) {
            Add-ScanError `
                -Stage "EnumerateFile" `
                -Path $EnumerationError.TargetObject `
                -Identity $null `
                -ErrorRecord $EnumerationError
        }
    }
    catch {
        Add-ScanError `
            -Stage "EnumerateFiles" `
            -Path $RootPath `
            -Identity $null `
            -ErrorRecord $_

        $Files = @()
    }

    $FileNumber = 0

    foreach ($File in $Files) {
        $FileNumber++

        if (($FileNumber % 1000) -eq 0) {
            Write-Log "$FileNumber von $($Files.Count) Dateien verarbeitet."
        }

        Process-FileSystemItem `
            -Item $File `
            -ItemType "File"
    }
}

# ------------------------------------------------------------
# Konsolidierte Benutzerberechtigungen
# ------------------------------------------------------------

Write-Log "Erstelle konsolidierte Benutzerübersicht."

$UserEffectiveSummary = [System.Collections.Generic.List[object]]::new()

$GroupedUserAccess = $UserAccess |
    Group-Object -Property UserSID, ItemPath

foreach ($AccessGroup in $GroupedUserAccess) {
    $Rows = @($AccessGroup.Group)

    if ($Rows.Count -eq 0) {
        continue
    }

    [uint32]$AllowMask = 0
    [uint32]$DenyMask = 0

    foreach ($Row in $Rows) {
        [uint32]$CurrentMask = [uint32]$Row.RightsMask

        if ($Row.AccessControlType -eq "Allow") {
            $AllowMask = $AllowMask -bor $CurrentMask
        }
        elseif ($Row.AccessControlType -eq "Deny") {
            $DenyMask = $DenyMask -bor $CurrentMask
        }
    }

    [uint32]$DerivedMask = $AllowMask -band (-bnot $DenyMask)

    $PermissionSources = @(
        $Rows |
            ForEach-Object {
                if ($_.AssignmentType -eq "Direct") {
                    "Direct:$($_.PermissionSource)"
                }
                elseif ($_.GroupPath) {
                    "Group:$($_.GroupPath)"
                }
                else {
                    "Group:$($_.PermissionSource)"
                }
            } |
            Sort-Object -Unique
    ) -join " | "

    $UserEffectiveSummary.Add([pscustomobject][ordered]@{
        ItemPath             = $Rows[0].ItemPath
        ItemType             = $Rows[0].ItemType
        UserName             = $Rows[0].UserName
        SamAccountName       = $Rows[0].SamAccountName
        UserPrincipalName    = $Rows[0].UserPrincipalName
        UserSID              = $Rows[0].UserSID
        UserEnabled          = $Rows[0].UserEnabled
        AllowRights          = Convert-RightsMaskToText -Mask $AllowMask
        AllowMask            = $AllowMask
        DenyRights           = Convert-RightsMaskToText -Mask $DenyMask
        DenyMask             = $DenyMask
        DerivedRights        = Convert-RightsMaskToText -Mask $DerivedMask
        DerivedRightsMask    = $DerivedMask
        PermissionSources    = $PermissionSources
        AssignmentCount      = $Rows.Count
        EvaluationNote       = "Technische NTFS-ACL-Ableitung; kein vollständiger Windows-Benutzertoken-Test"
    })
}

# ------------------------------------------------------------
# Export
# ------------------------------------------------------------

Write-Log "Exportiere Ergebnisse."

$OutputFiles = [ordered]@{
    AclRaw = Join-Path $OutputPath "01_ACL_Raw.csv"
    GroupStructure = Join-Path $OutputPath "02_GroupStructure.csv"
    UserAccess = Join-Path $OutputPath "03_UserAccess.csv"
    UserEffectiveSummary = Join-Path $OutputPath "04_UserEffectiveSummary.csv"
    UnresolvedIdentities = Join-Path $OutputPath "05_UnresolvedIdentities.csv"
    ScanErrors = Join-Path $OutputPath "06_ScanErrors.csv"
    Manifest = Join-Path $OutputPath "AuditManifest.json"
}

$AclRaw |
    Sort-Object ItemPath, IdentityReference, AccessControlType |
    Export-Csv `
        -LiteralPath $OutputFiles.AclRaw `
        -Delimiter $CsvDelimiter `
        -NoTypeInformation `
        -Encoding UTF8

$GroupStructure |
    Sort-Object SourceGroup, GroupPath, MemberType, MemberSamAccountName |
    Export-Csv `
        -LiteralPath $OutputFiles.GroupStructure `
        -Delimiter $CsvDelimiter `
        -NoTypeInformation `
        -Encoding UTF8

$UserAccess |
    Sort-Object SamAccountName, ItemPath, AccessControlType, PermissionSource |
    Export-Csv `
        -LiteralPath $OutputFiles.UserAccess `
        -Delimiter $CsvDelimiter `
        -NoTypeInformation `
        -Encoding UTF8

$UserEffectiveSummary |
    Sort-Object SamAccountName, ItemPath |
    Export-Csv `
        -LiteralPath $OutputFiles.UserEffectiveSummary `
        -Delimiter $CsvDelimiter `
        -NoTypeInformation `
        -Encoding UTF8

$UnresolvedIdentities |
    Sort-Object Identity, Path -Unique |
    Export-Csv `
        -LiteralPath $OutputFiles.UnresolvedIdentities `
        -Delimiter $CsvDelimiter `
        -NoTypeInformation `
        -Encoding UTF8

$ScanErrors |
    Sort-Object Stage, Path |
    Export-Csv `
        -LiteralPath $OutputFiles.ScanErrors `
        -Delimiter $CsvDelimiter `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Prüfsummen und Manifest
# ------------------------------------------------------------

$ScriptEnd = Get-Date

$ResultFileHashes = foreach ($FilePath in @(
    $OutputFiles.AclRaw,
    $OutputFiles.GroupStructure,
    $OutputFiles.UserAccess,
    $OutputFiles.UserEffectiveSummary,
    $OutputFiles.UnresolvedIdentities,
    $OutputFiles.ScanErrors
)) {
    if (Test-Path -LiteralPath $FilePath) {
        $Hash = Get-FileHash `
            -LiteralPath $FilePath `
            -Algorithm SHA256

        [ordered]@{
            FileName = Split-Path $FilePath -Leaf
            SHA256   = $Hash.Hash
            Length   = (Get-Item -LiteralPath $FilePath).Length
        }
    }
}

$Manifest = [ordered]@{
    AuditName = "WVAG Berechtigungspruefung 2026"
    RunId = $RunId
    ScriptStart = $ScriptStart.ToString("o")
    ScriptEnd = $ScriptEnd.ToString("o")
    DurationSeconds = :Round(
        ($ScriptEnd - $ScriptStart).TotalSeconds,
        2
    )
    ExecutingUser = $ExecutingUser
    ComputerName = $ComputerName
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    RootPath = $RootPath
    OutputPath = $OutputPath
    IncludeFiles = [bool]$IncludeFiles
    ExcludeDisabledUsers = [bool]$ExcludeDisabledUsers
    ExcludedUsersCsv = $ExcludedUsersCsv
    CsvDelimiter = [string]$CsvDelimiter
    Counts = [ordered]@{
        DirectoriesEnumerated = $Directories.Count + 1
        FilesEnumerated = $Files.Count
        AclRows = $AclRaw.Count
        GroupStructureRows = $GroupStructure.Count
        UserAccessRows = $UserAccess.Count
        UserEffectiveSummaryRows = $UserEffectiveSummary.Count
        UnresolvedIdentityRows = $UnresolvedIdentities.Count
        ScanErrorRows = $ScanErrors.Count
    }
    Limitations = @(
        "SMB-Share-Berechtigungen sind nicht enthalten.",
        "Lokale Gruppen auf entfernten Fileservern werden nicht aufgelöst.",
        "Well-known Principals werden dokumentiert, aber nicht auf einzelne Benutzer expandiert.",
        "Dynamic Access Control und Central Access Policies sind nicht enthalten.",
        "DerivedRights ist eine ACL-Ableitung und kein vollständiger Windows Effective Access Token-Test."
    )
    Files = $ResultFileHashes
}

$Manifest |
    ConvertTo-Json -Depth 10 |
    Set-Content `
        -LiteralPath $OutputFiles.Manifest `
        -Encoding UTF8

$ManifestHash = Get-FileHash `
    -LiteralPath $OutputFiles.Manifest `
    -Algorithm SHA256

Write-Log "Berechtigungsprüfung abgeschlossen."
Write-Log "Ausgabeverzeichnis: $OutputPath"
Write-Log "Verzeichnisse: $($Directories.Count + 1)"
Write-Log "Dateien: $($Files.Count)"
Write-Log "ACL-Einträge: $($AclRaw.Count)"
Write-Log "Benutzerzugriffszeilen: $($UserAccess.Count)"
Write-Log "Nicht auflösbare Identitäten: $($UnresolvedIdentities.Count)"
Write-Log "Fehler: $($ScanErrors.Count)"
Write-Log "Manifest SHA-256: $($ManifestHash.Hash)"