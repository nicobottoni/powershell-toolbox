function Get-AssessmentTrust {

    $domains = (Get-ADForest).Domains

    foreach ($domainName in $domains) {

        $trusts = Get-ADTrust `
            -Filter * `
            -Server $domainName

        foreach ($trust in $trusts) {

            [PSCustomObject]@{
                Source                  = $trust.Source
                Target                  = $trust.Target
                Direction               = $trust.Direction
                TrustType               = $trust.TrustType
                ForestTransitive        = $trust.ForestTransitive
                IntraForest             = $trust.IntraForest
                SelectiveAuthentication = $trust.SelectiveAuthentication
                SIDFilteringForestAware = $trust.SIDFilteringForestAware
                SIDFilteringQuarantined = $trust.SIDFilteringQuarantined
            }
        }
    }
}

Export-ModuleMember -Function Get-AssessmentTrust