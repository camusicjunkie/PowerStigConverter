function New-AnsibleAccountPolicyTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { return }

            $navParams = @{ TaskId = $rule.Id; TaskName = $rule.PolicyName; StigName = $StigName }
            $policyName = $rule.PolicyName -replace '/|\s', '_' -replace ':'

            $policyValue = Get-AnsibleOrganizationValue -Rule $rule -StigName $StigName
            $parsedPolicyValue = if ([int32]::TryParse($policyValue, [ref] $null)) { [int] $policyValue } else { $policyValue }

            $task = [ordered] @{
                'name' = '{0} | {1} | {2}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.PolicyName
                'community.windows.win_security_policy' = [ordered] @{
                    'section' = $accountPolicyData[$policyName].Section
                    'key' = $accountPolicyData[$policyName].Value
                    'value' = $parsedPolicyValue
                }
                'when' = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            @{
                Rule = $rule
                Task = $task
            }
        }
    }
}
