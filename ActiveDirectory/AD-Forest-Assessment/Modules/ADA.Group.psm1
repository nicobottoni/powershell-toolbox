function Get-AssessmentGroup {

    $domains = (Get-ADForest).Domains

    foreach ($domainName in $domains) {

        $groups = Get-ADGroup `
            -Filter * `
            -Server $domainName `
            -Properties Description,
                        GroupCategory,
                        GroupScope,
                        Members,
                        WhenCreated

        foreach ($group in $groups) {

            $memberCount = @($group.Members).Count
            $nestedGroupCount = 0

            if ($memberCount -gt 0) {

                try {
            
                    $nestedGroupCount = @(
                        Get-ADGroupMember `
                            -Identity $group.DistinguishedName `
                            -Server $domainName `
                            -ErrorAction Stop |
                        Where-Object ObjectClass -eq 'group'
                    ).Count
            
                }
                catch {
            
                    $nestedGroupCount = $null
                }
            }

            [PSCustomObject]@{
                Domain           = $domainName
                GroupName        = $group.Name
                SamAccountName   = $group.SamAccountName
                GroupCategory    = $group.GroupCategory
                GroupScope       = $group.GroupScope
                Description      = $group.Description
                MemberCount      = $memberCount
                NestedGroupCount = $nestedGroupCount
                IsEmpty          = ($memberCount -eq 0)
                HasDescription   = (-not [string]::IsNullOrWhiteSpace($group.Description))
                WhenCreated      = $group.WhenCreated
                MembershipQuerySuccessful = ($null -ne $nestedGroupCount)
            }
        }
    }
}

Export-ModuleMember -Function Get-AssessmentGroup