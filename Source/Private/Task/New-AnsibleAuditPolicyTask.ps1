function New-AnsibleAuditPolicyTask {
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

            $name = "{0} {1}" -f $rule.SubCategory, $rule.AuditFlag

            $task = [ordered] @{
                'name' = '{0} | {1} | {2} - {3}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.Subcategory, $rule.AuditFlag
                'community.windows.win_audit_policy_system' = [ordered] @{
                    'subcategory' = $rule.Subcategory
                    'audit_type' = $rule.AuditFlag
                }
                'when' = New-AnsibleVariable -TaskId $rule.Id -TaskName $name -Type Conditional -StigName $StigName
            }

            Write-Verbose "  Task: $($task.name)"

            @{
                Rule = $rule
                Name = $name
                Task = $task
            }
        }
    }
}
