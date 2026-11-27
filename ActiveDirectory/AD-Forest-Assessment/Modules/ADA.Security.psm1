function Get-AssessmentPrivilegedAccount {

    $forest = Get-ADForest
    $domains = $forest.Domains

    foreach ($domainName in $domains) {

        $domain = Get-ADDomain `
            -Identity $domainName `
            -Server $domainName

        $domainSid = $domain.DomainSID.Value

        # Domain-specific and well-known privileged groups
        $privilegedGroupDefinitions = @(
            @{
                Key = 'DomainAdmins'
                SID = "$domainSid-512"
            }
            @{
                Key = 'Administrators'
                SID = 'S-1-5-32-544'
            }
            @{
                Key = 'AccountOperators'
                SID = 'S-1-5-32-548'
            }
            @{
                Key = 'ServerOperators'
                SID = 'S-1-5-32-549'
            }
            @{
                Key = 'PrintOperators'
                SID = 'S-1-5-32-550'
            }
            @{
                Key = 'BackupOperators'
                SID = 'S-1-5-32-551'
            }
        )

        # Enterprise Admins and Schema Admins only exist
        # in the forest root domain
        if ($domainName -eq $forest.RootDomain) {

            $privilegedGroupDefinitions += @(
                @{
                    Key = 'SchemaAdmins'
                    SID = "$domainSid-518"
                }
                @{
                    Key = 'EnterpriseAdmins'
                    SID = "$domainSid-519"
                }
            )
        }

        foreach ($groupDefinition in $privilegedGroupDefinitions) {

            try {

                $group = Get-ADGroup `
                    -Identity $groupDefinition.SID `
                    -Server $domainName `
                    -Properties SID `
                    -ErrorAction Stop

            }
            catch {

                continue
            }

            # Collect direct group members
            try {

                $directMembers = @(
                    Get-ADGroupMember `
                        -Identity $group.DistinguishedName `
                        -Server $domainName `
                        -ErrorAction Stop
                )

            }
            catch {

                continue
            }

            # Store the SIDs of direct user members
            $directUserSids = @(
                $directMembers |
                    Where-Object ObjectClass -eq 'user' |
                    ForEach-Object {
                        $_.SID.Value
                    }
            )

            # Resolve all users recursively
            try {

                $recursiveUserMembers = @(
                    Get-ADGroupMember `
                        -Identity $group.DistinguishedName `
                        -Recursive `
                        -Server $domainName `
                        -ErrorAction Stop |
                    Where-Object ObjectClass -eq 'user'
                )

            }
            catch {

                continue
            }

            foreach ($member in $recursiveUserMembers) {

                if ($member.SID.Value -in $directUserSids) {
                    $membershipType = 'Direct'
                }
                else {
                    $membershipType = 'Indirect'
                }

                try {

                    $user = Get-ADUser `
                        -Identity $member.DistinguishedName `
                        -Server $domainName `
                        -Properties Enabled,
                                    LastLogonDate,
                                    PasswordLastSet,
                                    PasswordNeverExpires,
                                    PasswordNotRequired,
                                    WhenCreated `
                        -ErrorAction Stop

                }
                catch {

                    continue
                }

                [PSCustomObject]@{
                    Domain               = $domainName
                    PrivilegedGroup      = $group.Name
                    PrivilegedGroupKey   = $groupDefinition.Key
                    PrivilegedGroupSID   = $group.SID.Value
                    MembershipType       = $membershipType
                    SamAccountName       = $user.SamAccountName
                    Enabled              = $user.Enabled
                    LastLogonDate        = $user.LastLogonDate
                    PasswordLastSet      = $user.PasswordLastSet
                    PasswordNeverExpires = $user.PasswordNeverExpires
                    PasswordNotRequired  = $user.PasswordNotRequired
                    WhenCreated          = $user.WhenCreated
                }
            }
        }
    }
}




function Test-AssessmentPrivilegedAccount {

    param(
        [Parameter(Mandatory)]
        [object[]]$PrivilegedAccounts,

        [int]$InactiveDays = 90
    )

    $inactiveDate = (Get-Date).AddDays(-$InactiveDays)

    $uniqueAccounts = $PrivilegedAccounts |
        Group-Object Domain, SamAccountName

    foreach ($accountGroup in $uniqueAccounts) {

        $account = $accountGroup.Group | Select-Object -First 1

        $privilegedGroups = @(
            $accountGroup.Group.PrivilegedGroup |
                Sort-Object -Unique
        ) -join ', '

        if ($account.Enabled -and $account.PasswordNeverExpires) {

            [PSCustomObject]@{
                Severity       = 'High'
                Category       = 'Privileged Access'
                Domain         = $account.Domain
                ObjectType     = 'User'
                ObjectName     = $account.SamAccountName
                Finding        = 'Enabled privileged account has a non-expiring password'
                Details        = "Privileged groups: $privilegedGroups"
                Recommendation = 'Review whether the account requires a non-expiring password and implement an appropriate privileged account or managed service account design.'
            }
        }

        if ($account.PasswordNotRequired) {

            [PSCustomObject]@{
                Severity       = 'Critical'
                Category       = 'Privileged Access'
                Domain         = $account.Domain
                ObjectType     = 'User'
                ObjectName     = $account.SamAccountName
                Finding        = 'Privileged account does not require a password'
                Details        = "Privileged groups: $privilegedGroups"
                Recommendation = 'Remove the PasswordNotRequired setting immediately and enforce the applicable password policy.'
            }
        }

        if ($account.Enabled -and $null -eq $account.LastLogonDate) {

            [PSCustomObject]@{
                Severity       = 'Medium'
                Category       = 'Privileged Access'
                Domain         = $account.Domain
                ObjectType     = 'User'
                ObjectName     = $account.SamAccountName
                Finding        = 'Enabled privileged account has never logged on'
                Details        = "Privileged groups: $privilegedGroups"
                Recommendation = 'Verify whether the account is required. Disable or remove unnecessary privileged access.'
            }
        }
        elseif (
            $account.Enabled -and
            $account.LastLogonDate -lt $inactiveDate
        ) {

            [PSCustomObject]@{
                Severity       = 'High'
                Category       = 'Privileged Access'
                Domain         = $account.Domain
                ObjectType     = 'User'
                ObjectName     = $account.SamAccountName
                Finding        = "Enabled privileged account has been inactive for more than $InactiveDays days"
                Details        = "Last logon: $($account.LastLogonDate); Privileged groups: $privilegedGroups"
                Recommendation = 'Review the account requirement and remove or disable unnecessary privileged access.'
            }
        }

        if (-not $account.Enabled) {

            [PSCustomObject]@{
                Severity       = 'Low'
                Category       = 'Privileged Access'
                Domain         = $account.Domain
                ObjectType     = 'User'
                ObjectName     = $account.SamAccountName
                Finding        = 'Disabled account remains a member of privileged groups'
                Details        = "Privileged groups: $privilegedGroups"
                Recommendation = 'Remove unnecessary privileged group memberships from the disabled account.'
            }
        }
    }
}




function Test-AssessmentUserSecurity {

    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Users,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$PrivilegedAccounts
    )

    # Build a lookup table containing all unique privileged accounts
    $privilegedAccountLookup = @{}

    foreach ($privilegedAccount in $PrivilegedAccounts) {

        $accountKey = '{0}\{1}' -f `
            $privilegedAccount.Domain.ToLowerInvariant(),
            $privilegedAccount.SamAccountName.ToLowerInvariant()

        $privilegedAccountLookup[$accountKey] = $true
    }

    foreach ($user in $Users) {
        
        # Interdomain trust accounts are not normal user accounts
        # and must not be evaluated by user security checks.
        if ($user.IsInterdomainTrustAccount) {
            continue
        }

        if (-not $user.Enabled) {
            continue
        }

        $accountKey = '{0}\{1}' -f `
            $user.Domain.ToLowerInvariant(),
            $user.SamAccountName.ToLowerInvariant()

        $isPrivileged = $privilegedAccountLookup.ContainsKey($accountKey)

        # Privileged accounts are already evaluated separately
        if ($isPrivileged) {
            continue
        }

        if ($user.PasswordNotRequired) {

            [PSCustomObject]@{
                Severity       = 'Critical'
                Category       = 'User Account Security'
                Domain         = $user.Domain
                ObjectType     = 'User'
                ObjectName     = $user.SamAccountName
                Finding        = 'Enabled user account does not require a password'
                Details        = 'The PasswordNotRequired attribute is enabled for this account.'
                Recommendation = 'Remove the PasswordNotRequired setting and verify that the applicable domain password policy is enforced.'
            }
        }

        if ($user.PasswordNeverExpires) {

            [PSCustomObject]@{
                Severity       = 'Medium'
                Category       = 'User Account Security'
                Domain         = $user.Domain
                ObjectType     = 'User'
                ObjectName     = $user.SamAccountName
                Finding        = 'Enabled user account has a non-expiring password'
                Details        = 'The PasswordNeverExpires attribute is enabled for this non-privileged account.'
                Recommendation = 'Verify whether the setting is required. For technical identities, consider a group Managed Service Account where supported.'
            }
        }
    }
}




function Test-AssessmentComputerSecurity {

    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Computers,

        [int]$InactiveDays = 90,

        [int]$NewComputerGraceDays = 20
    )

    $graceDate = (Get-Date).AddDays(-$NewComputerGraceDays)

    foreach ($computer in $Computers) {

        if (-not $computer.Enabled) {
            continue
        }

        if (
            $computer.NeverLoggedOn -and
            $computer.WhenCreated -lt $graceDate
        ) {

            [PSCustomObject]@{
                Severity       = 'Medium'
                Category       = 'Computer Account Security'
                Domain         = $computer.Domain
                ObjectType     = 'Computer'
                ObjectName     = $computer.ComputerName
                Finding        = "Enabled computer account has never logged on and is older than $NewComputerGraceDays days"
                Details        = "Created: $($computer.WhenCreated); Operating system: $($computer.OperatingSystem)"
                Recommendation = 'Verify whether the computer account is required. Remove or disable stale computer accounts after confirming that the associated system no longer exists.'
            }

            # Do not generate an additional inactivity finding
            # for the same never-used computer account.
            continue
        }

        if ($computer.IsInactive) {

            [PSCustomObject]@{
                Severity       = 'Medium'
                Category       = 'Computer Account Security'
                Domain         = $computer.Domain
                ObjectType     = 'Computer'
                ObjectName     = $computer.ComputerName
                Finding        = "Enabled computer account has been inactive for more than $InactiveDays days"
                Details        = "Last logon: $($computer.LastLogonDate); Operating system: $($computer.OperatingSystem)"
                Recommendation = 'Verify whether the computer account is still required. Disable or remove stale computer accounts in accordance with the organization retention process.'
            }
        }
    }
}




Export-ModuleMember -Function @(
    'Get-AssessmentPrivilegedAccount'
    'Test-AssessmentPrivilegedAccount'
    'Test-AssessmentUserSecurity'
    'Test-AssessmentComputerSecurity'
)