function New-AnsibleSecurityOptionTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{}
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $navParams = @{ TaskId = $rule.Id; TaskName = $rule.OptionName; StigName = $StigName }
            $optionName = $rule.OptionName -replace '/|\s', '_' -replace ':'

            $organizationValue = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType 'SecurityOption' -StigName $StigName -OrganizationalSetting $OrganizationalSetting
            $optionValue = $organizationValue.Value

            $task = [ordered] @{
                'name' = '{0} | {1} | {2}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.OptionName
                'community.windows.win_security_policy' = [ordered] @{
                    'section' = $securityOptionData[$optionName].Section
                    'key' = $securityOptionData[$optionName].Value
                    'value' = $optionValue
                }
                'when' = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            @{
                Rule = $rule
                Task = Add-AnsibleOrganizationValueAssert -Task $task -OrganizationValue $organizationValue
            }
        }
    }
}
