function New-AnsiblePermissionTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    begin {
        $taskGroups = @{}
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { return }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $parsedPath = [System.Environment]::ExpandEnvironmentVariables($rule.Path)
            $path = if (Test-Path $parsedPath) { $parsedPath } else { $rule.Path }

            $task = foreach ($entry in $rule.AccessControlEntry.Entry) {
                $flags = Get-AnsibleInheritanceFlag -Resource $rule.DscResource -Inheritance $entry.Inheritance
                $name = '{0} | {1} | Set {2} permissions for {3} on {4}' -f $rule.Id, $rule.Severity.ToUpper(), $entry.Rights, $entry.Principal, $parsedPath
                $type = if ([string]::IsNullOrEmpty($entry.Type)) { 'Allow' } else { $entry.Type }

                [ordered] @{
                    'name' = $name
                    'ansible.windows.win_acl' = [ordered] @{
                        'path' = $path
                        'user' = $entry.Principal
                        'rights' = $entry.Rights
                        'type' = $type
                        # state = ''
                        'inherit' = $flags.InheritanceFlag
                        'propagation' = $flags.PropagationFlag
                    }
                }

                Write-Verbose "  Task: $name"
            }

            if (-not $taskGroups.ContainsKey($baseId)) {
                $taskGroups[$baseId] = @{
                    Rule = @{
                        Id = $baseId
                        Severity = $rule.Severity
                        OrganizationValueRequired = $rule.OrganizationValueRequired
                    }
                    Name = $parsedPath
                    Task = [ordered] @{
                        'name' = '{0} | {1} | Set permissions on {2}' -f $baseId, $rule.Severity.ToUpper(), $parsedPath
                        'block' = @()
                        'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedPath -Type Conditional -StigName $StigName
                    }
                }

                Write-Verbose "  TaskGroup: $($taskGroups[$baseId].Task.name)"

                $taskGroups[$baseId].Task.block += $task
            }
            else {
                $taskGroups[$baseId].Task.block += $task
            }
        }
    }
    end {
        if ($null -ne $previousId) {
            $taskGroups[$previousId]
        }
    }
}
