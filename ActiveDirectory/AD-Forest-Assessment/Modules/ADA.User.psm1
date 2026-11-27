function Get-AssessmentUser {

    param(
        [int]$InactiveDays = 90
    )

    $domains = (Get-ADForest).Domains
    $inactiveDate = (Get-Date).AddDays(-$InactiveDays)

    # Detect interdomain trust accounts
    $interdomainTrustAccountFlag = 0x0800

    foreach ($domainName in $domains) {

        $users = Get-ADUser `
            -Filter * `
            -Server $domainName `
            -Properties DisplayName,
                        Enabled,
                        LastLogonDate,
                        PasswordLastSet,
                        PasswordNeverExpires,
                        PasswordNotRequired,
                        LockedOut,
                        UserAccountControl,
                        WhenCreated

        foreach ($user in $users) {
            
            $isInterdomainTrustAccount = (
                $user.UserAccountControl -band $interdomainTrustAccountFlag
            ) -ne 0

            $neverLoggedOn = $false
            $isInactive = $false

            if ($user.Enabled) {

                if ($null -eq $user.LastLogonDate) {
                    $neverLoggedOn = $true
                }
                elseif ($user.LastLogonDate -lt $inactiveDate) {
                    $isInactive = $true
                }
            }

            [PSCustomObject]@{
                Domain               = $domainName
                SamAccountName       = $user.SamAccountName
                DisplayName          = $user.DisplayName
                Enabled              = $user.Enabled
                LastLogonDate        = $user.LastLogonDate
                PasswordLastSet      = $user.PasswordLastSet
                PasswordNeverExpires = $user.PasswordNeverExpires
                PasswordNotRequired  = $user.PasswordNotRequired
                LockedOut            = $user.LockedOut
                WhenCreated          = $user.WhenCreated
                NeverLoggedOn        = $neverLoggedOn
                IsInactive           = $isInactive
                IsInterdomainTrustAccount = $isInterdomainTrustAccount
            }
        }
    }
}

Export-ModuleMember -Function Get-AssessmentUser