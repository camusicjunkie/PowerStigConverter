function New-AnsibleWindowsFeatureTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [string] $Path
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $navParams = @{ TaskId = $rule.Id; TaskName = $name; StigName = $StigName }
            $name = '{0} {1}' -f $rule.Name, $rule.Ensure

            $task = [ordered] @{
                name = '{0} | {1} | Set {2} to {3}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.Name, $rule.Ensure
                'ansible.windows.win_feature' = [ordered] @{
                    'name' = $rule.Name
                    'state' = $rule.Ensure
                }
                when = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            # TODO: Add logic for block. Some rules have nested tasks.
            @{
                Rule = $rule
                Name = $name
                Task = $task
            }
        }
    }
}
