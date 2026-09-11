function New-AnsibleUserRightTask {
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

            $navParams = @{ TaskId = $rule.Id; TaskName = $rule.DisplayName; StigName = $StigName }
            $organizationValue = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType 'UserRight' -StigName $StigName -OrganizationalSetting $OrganizationalSetting
            $identity = $organizationValue.Value

            $task = [ordered] @{
                'name' = '{0} | {1} | {2}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.DisplayName
                'ansible.windows.win_user_right' = [ordered] @{
                    'name' = $rule.Constant
                    'action' = if ($rule.Force -eq 'True') { 'set' } else { 'add' }
                    'users' = $identity
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
