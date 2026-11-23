function Get-AssessmentUser {

    param(
        [int]$InactiveDays = 90
    )

    $domains = (Get-ADForest).Domains
    $inactiveDate = (Get-Date).AddDays(-$InactiveDays)

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
                        WhenCreated

        foreach ($user in $users) {

            $neverLoggedOn = $false
            $inactiveOver90Days = $false

            if ($user.Enabled) {

                if ($null -eq $user.LastLogonDate) {
                    $neverLoggedOn = $true
                }
                elseif ($user.LastLogonDate -lt $inactiveDate) {
                    $inactiveOver90Days = $true
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
                InactiveOver90Days   = $inactiveOver90Days
            }
        }
    }
}

Export-ModuleMember -Function Get-AssessmentUser