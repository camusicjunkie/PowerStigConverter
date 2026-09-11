function Export-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Rule,

        [string] $StigName,

        # The org settings loaded once by Get-PowerStigOrgSetting, keyed by rule id.
        [Parameter()]
        [hashtable] $OrgSetting = @{},

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    begin {
        $organization = [System.Collections.SortedList]::new()
    }
    process {
        $ruleName = $Rule.PowerStigRule -replace 'Rule'
        foreach ($rule in $Rule.StigRule) {

            $node = $OrgSetting[$rule.Id]

            $taskName = if ($ruleName -eq 'IisLogging') { 'logpath' } else { $rule.($organizationData[$ruleName]['Name']) }
            $nodeValue = if ($ruleName -eq 'IisLogging') { $null } else { $node.($organizationData[$ruleName]['Value']) }

            $navParams = @{
                TaskId = $rule.id
                TaskName = $taskName
                NodeValue = $nodeValue
                StigName = $StigName
            }
            $organizationVariable = New-AnsibleVariable @navParams -Type OrganizationValue
            $organization.Add($rule.Id, $organizationVariable)
        }
    }
    end {
        $content = @(@'
{0}_cat1: true
{0}_cat2: true
{0}_cat3: true

'@ -f (New-AnsibleVariable -StigName $StigName -Type OrganizationValueGroup))

        if ($organization.Count -gt 0) { $content += $organization.Values }

        Save-AnsibleRoleFile -OutputPath $OutputPath -Content ([ordered] @{ main_default_org = $content })
    }
}
