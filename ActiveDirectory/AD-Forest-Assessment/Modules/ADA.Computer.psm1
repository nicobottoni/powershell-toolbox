function Get-AssessmentComputer {

    param(
        [int]$InactiveDays = 90
    )

    $domains = (Get-ADForest).Domains
    $inactiveDate = (Get-Date).AddDays(-$InactiveDays)

    foreach ($domainName in $domains) {

        $computers = Get-ADComputer `
            -Filter * `
            -Server $domainName `
            -Properties Enabled,
                        OperatingSystem,
                        OperatingSystemVersion,
                        LastLogonDate,
                        PasswordLastSet,
                        WhenCreated

        foreach ($computer in $computers) {

            $neverLoggedOn = $false
            $isInactive = $false

            if ($computer.Enabled) {

                if ($null -eq $computer.LastLogonDate) {
                    $neverLoggedOn = $true
                }
                elseif ($computer.LastLogonDate -lt $inactiveDate) {
                    $isInactive = $true
                }
            }

            [PSCustomObject]@{
                Domain                 = $domainName
                ComputerName           = $computer.Name
                Enabled                = $computer.Enabled
                OperatingSystem        = $computer.OperatingSystem
                OperatingSystemVersion = $computer.OperatingSystemVersion
                LastLogonDate          = $computer.LastLogonDate
                PasswordLastSet        = $computer.PasswordLastSet
                WhenCreated            = $computer.WhenCreated
                NeverLoggedOn          = $neverLoggedOn
                IsInactive             = $isInactive
            }
        }
    }
}

Export-ModuleMember -Function Get-AssessmentComputer
