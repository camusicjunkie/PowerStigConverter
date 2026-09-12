function Export-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Rule,

        [string] $StigName,

        # The org settings loaded once by Get-PowerStigOrgSetting, keyed by rule id.
        [Parameter()]
        [hashtable] $OrganizationalSetting = @{},

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

            $resolution = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType $ruleType `
                -StigName $StigName -OrganizationalSetting $OrganizationalSetting

            $declarations = @(
                # One declaration per organization variable the rule needs - flat rather than a
                # mapping, so a single field can be overridden with -e and an assert can name the
                # one that is unanswered.
                foreach ($variable in $resolution.Variable) { $variable.Declaration }

                # The IIS log path is the other way round: no org settings attribute feeds it, so
                # it is not an organization value and never appears among them. Every IisLogging
                # rule still declares it blank for the site to fill in, because the task
                # references it whether or not the rule's other values are organization values,
                # and a reference with no declaration fails the play on an undefined variable.
                # New-AnsibleIisLoggingTask builds the reference from the same task name.
                if ($ruleType -eq 'IisLogging') {
                    New-AnsibleVariable -TaskId $rule.Id -TaskName 'LogPath' -StigName $StigName -Type OrganizationValue
                }
            )

            foreach ($declaration in $declarations) {
                # Sub-rules collapse onto the same variable when they share a field.
                if (-not $organization.ContainsKey($declaration)) {
                    $organization.Add($declaration, $declaration)
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
