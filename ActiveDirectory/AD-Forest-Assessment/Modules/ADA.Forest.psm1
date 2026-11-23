function Get-AssessmentForest {

    $forest = Get-ADForest

    [PSCustomObject]@{
        ForestName         = $forest.Name
        ForestMode         = $forest.ForestMode
        RootDomain         = $forest.RootDomain
        Domains            = ($forest.Domains -join ", ")
        GlobalCatalogCount = $forest.GlobalCatalogs.Count
        SchemaMaster       = $forest.SchemaMaster
        DomainNamingMaster = $forest.DomainNamingMaster
    }
}

Export-ModuleMember -Function Get-AssessmentForest