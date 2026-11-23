function Get-AssessmentDomainController {

    $domains = (Get-ADForest).Domains

    foreach ($domainName in $domains) {

        $domainControllers = Get-ADDomainController `
            -Filter * `
            -Server $domainName

        foreach ($dc in $domainControllers) {

            [PSCustomObject]@{
                HostName          = $dc.HostName
                Domain            = $dc.Domain
                Site              = $dc.Site
                IPv4Address       = $dc.IPv4Address
                OperatingSystem   = $dc.OperatingSystem
                OperatingSystemVersion = $dc.OperatingSystemVersion
                IsGlobalCatalog   = $dc.IsGlobalCatalog
                IsReadOnly        = $dc.IsReadOnly
            }
        }
    }
}

Export-ModuleMember -Function Get-AssessmentDomainController