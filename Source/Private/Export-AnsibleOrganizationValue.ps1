function Export-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Rule,

        [string] $StigName,

        # The org settings loaded once by Get-PowerStigOrgSetting, keyed by rule id.
        [Parameter()]
        [hashtable] $OrganizationalSetting = @{}
    )

    begin {
        $organization = [System.Collections.SortedList]::new()
    }
    process {
        $ruleType = $Rule.PowerStigRule -replace 'Rule'
        $hasOrganizationValue = $script:organizationData.ContainsKey($ruleType)
        $hasRoleVariable = $script:roleVariableData.ContainsKey($ruleType)
        if (-not $hasOrganizationValue -and -not $hasRoleVariable) { return }

        foreach ($rule in $Rule.StigRule) {
            # A duplicate produces no task, so a variable for it would guard nothing.
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $declarations = @(
                # One declaration per organization variable the rule needs - flat rather than a
                # mapping, so a single field can be overridden with -e and an assert can name the
                # one that is unanswered.
                if ($hasOrganizationValue) {
                    $resolution = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType $ruleType `
                        -StigName $StigName -OrganizationalSetting $OrganizationalSetting
                    foreach ($variable in $resolution.Variable) { $variable.Declaration }
                }

                # Some role variables carry no organization value at all - the IIS log path and
                # site name are the other way round: no org settings attribute feeds them, so
                # they never appear above. A rule type that needs one still declares it blank for
                # the site to fill in, because the task references it regardless, and a reference
                # with no declaration fails the play on an undefined variable. RoleVariableData.psd1
                # names the task each rule type's generator builds the same reference from.
                if ($hasRoleVariable) {
                    foreach ($taskName in $script:roleVariableData[$ruleType]) {
                        New-AnsibleVariableLine -TaskId $rule.Id -TaskName $taskName -StigName $StigName
                    }
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

'@ -f (Get-AnsibleVariablePrefix -StigName $StigName))

        if ($organization.Count -gt 0) { $content += $organization.Values }

        [ordered] @{ main_default_org = $content }
    }
}
