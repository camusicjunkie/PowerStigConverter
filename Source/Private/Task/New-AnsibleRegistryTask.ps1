function New-AnsibleRegistryTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    begin {
        $taskGroups = @{}
        $previousId = $null
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ TaskId = $rule.Id; TaskName = $rule.ValueName; StigName = $StigName }

            $valueData = Get-AnsibleOrganizationValue -Rule $rule -RuleType 'Registry' -StigName $StigName
            $parsedValueData = if ([int32]::TryParse($valueData, [ref] $null)) { [int] $valueData } else { $valueData }
            $parsedValueName = if ($rule.Id -match '\.[a-z]$') { Split-Path -Path $rule.Key -Leaf } else { $rule.ValueName }

            $task = [ordered] @{
                name = '{0} | {1} | Set {2}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.ValueName
                'ansible.windows.win_regedit' = [ordered] @{
                    'path' = $rule.Key
                    'name' = $rule.ValueName
                    'data' = $parsedValueData
                    'type' = $rule.ValueType.ToLower()
                }
            }

            Write-Verbose "  Task: $($task.name)"

            if ($rule.Id -match '\.[a-z]$') {
                if ($null -ne $previousId -and $previousId -ne $baseId) {
                    $taskGroups[$previousId]
                }

                if (-not $taskGroups.ContainsKey($baseId)) {
                    $taskGroups[$baseId] = @{
                        Rule = $rule
                        Name = $parsedValueName
                        Task = [ordered] @{
                            'name' = '{0} | {1} | {2}' -f $baseId, $rule.Severity.ToUpper(), $parsedValueName
                            'block' = [System.Collections.ArrayList]::new()
                            'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedValueName -Type Conditional -StigName $StigName
                        }
                    }

                    Write-Verbose "  TaskGroup: $($taskGroups[$baseId].Task.name)"

                    $null = $taskGroups[$baseId].Task.block.Add($task)
                }
                else {
                    $null = $taskGroups[$baseId].Task.block.Add($task)
                }
                $previousId = $baseId
            }
            else {
                $task.when = New-AnsibleVariable @navParams -Type Conditional

                @{
                    Rule = $rule
                    Task = $task
                }
            }
        }
    }
    end {
        if ($null -ne $previousId) {
            $taskGroups[$previousId]
        }
    }
}
