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
        $ruleType = $Rule.PowerStigRule -replace 'Rule'
        if (-not $script:organizationData.ContainsKey($ruleType)) { return }

        foreach ($rule in $Rule.StigRule) {
            # A duplicate produces no task, so a variable for it would guard nothing.
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $node = $OrgSetting[$rule.Id]

            # One variable per field the task consumes. Flat rather than a mapping so a single
            # field can be overridden with -e and an assert can name the one that is missing.
            $fields = @(
                # Only a rule that leaves its value to the organization declares one.
                if ($rule.OrganizationValueRequired -eq $true) {
                    $script:organizationData[$ruleType]['Required']
                }

                # The IIS log path is the other way round: no org settings attribute feeds it,
                # so every IisLogging rule declares it blank for the site to fill in. The task
                # references it whether or not the rule's other values are organization values,
                # and a reference with no declaration fails the play on an undefined variable.
                if ($ruleType -eq 'IisLogging') { 'LogPath' }
            )

            foreach ($field in $fields) {
                $navParams = @{
                    TaskId = $rule.Id
                    TaskName = Get-AnsibleOrganizationTaskName -Rule $rule -RuleType $ruleType -Field $field
                    NodeValue = Get-AnsibleOrganizationDefaultValue -Node $node -RuleType $ruleType -Field $field
                    StigName = $StigName
                }
                $organizationVariable = New-AnsibleVariable @navParams -Type OrganizationValue

                # Sub-rules collapse onto the same variable when they share a field.
                if (-not $organization.ContainsKey($organizationVariable)) {
                    $organization.Add($organizationVariable, $organizationVariable)
                }
            }
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
