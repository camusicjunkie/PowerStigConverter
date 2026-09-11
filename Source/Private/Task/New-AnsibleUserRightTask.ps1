function New-AnsibleUserRightTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrgSetting
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $navParams = @{ TaskId = $rule.Id; TaskName = $rule.DisplayName; StigName = $StigName }
            $identity = Get-AnsibleOrganizationValue -Rule $rule -RuleType 'UserRight' -StigName $StigName -OrgSetting $OrgSetting

            $task = [ordered] @{
                'name' = '{0} | {1} | {2}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.DisplayName
                'ansible.windows.win_user_right' = [ordered] @{
                    'name' = $rule.Constant
                    'action' = if ($rule.Force -eq 'True') { 'set' } else { 'add' }
                    'users' = $identity -split ','
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
