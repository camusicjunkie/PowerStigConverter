function New-AnsibleAuditSettingTask {
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

            $navParams = @{ TaskId = $rule.Id; StigName = $StigName }

            $task = [ordered] @{
                'name' = '{0} | {1} | Audit that {2} {3} {4}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.Property, $rule.Operator, $rule.DesiredValue
                'ansible.windows.win_dsc' = [ordered] @{
                    'resource_name' = 'AuditSetting'
                    'Query' = $rule.Query
                    'Property' = $rule.Property
                    'DesiredValue' = $rule.DesiredValue
                    'Operator' = $rule.Operator
                }
                'when' = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            if ($rule.Namespace) { $task.'ansible.windows.win_dsc'.Namespace = $rule.Namespace }
            $name = '{0} {1}' -f $rule.Property, $rule.DesiredValue

            @{
                Rule = $rule
                Name = $name
                Task = $task
            }
        }
    }
}
