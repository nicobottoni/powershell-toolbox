function Get-AssessmentPrivilegedAccount {

    $domains = (Get-ADForest).Domains

    $privilegedGroups = @(
        'Domain Admins'
        'Enterprise Admins'
        'Schema Admins'
        'Administrators'
        'Account Operators'
        'Backup Operators'
        'Server Operators'
        'Print Operators'
    )

    foreach ($domainName in $domains) {

        foreach ($groupName in $privilegedGroups) {

            $group = Get-ADGroup `
                -Filter "Name -eq '$groupName'" `
                -Server $domainName `
                -ErrorAction SilentlyContinue

            if ($null -eq $group) {
                continue
            }

            $members = Get-ADGroupMember `
                -Identity $group `
                -Server $domainName `
                -ErrorAction SilentlyContinue

            foreach ($member in $members) {

                # For now, assess user accounts only
                if ($member.ObjectClass -ne 'user') {
                    continue
                }

                $user = Get-ADUser `
                    -Identity $member `
                    -Server $domainName `
                    -Properties Enabled,
                                LastLogonDate,
                                PasswordLastSet,
                                PasswordNeverExpires,
                                PasswordNotRequired,
                                WhenCreated

                [PSCustomObject]@{
                    Domain               = $domainName
                    PrivilegedGroup      = $group.Name
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


Export-ModuleMember -Function @(
    'Get-AssessmentPrivilegedAccount'
    'Test-AssessmentPrivilegedAccount'
)