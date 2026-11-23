function Get-AssessmentDomain {

    $domains = (Get-ADForest).Domains

    foreach ($domainName in $domains) {

        $domain = Get-ADDomain -Identity $domainName

        [PSCustomObject]@{
            DomainName           = $domain.DNSRoot
            NetBIOSName          = $domain.NetBIOSName
            DomainMode           = $domain.DomainMode
            DistinguishedName    = $domain.DistinguishedName
            PDCEmulator          = $domain.PDCEmulator
            RIDMaster            = $domain.RIDMaster
            InfrastructureMaster = $domain.InfrastructureMaster
        }
    }
}

Export-ModuleMember -Function Get-AssessmentDomain