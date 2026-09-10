function New-AnsibleWebConfigurationPropertyTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [string] $StigId
    )

    begin {
        $taskGroups = @{}
        $previousId = $null
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { return }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ TaskId = $rule.Id; StigName = $StigName }
            $parsedConfigSection = if ($rule.Id -match '\.[a-z]$') { Split-Path -Path $rule.ConfigSection } else { $rule.ConfigSection }
            $website = New-AnsibleVariable @navParams -Type Organization -TaskName 'website'
            $websitePath = if ($StigId -match 'IIS_.+_Server') {
                if ($rule.ConfigSection -match '/system.web/') {
                    'MACHINE/WEBROOT'
                }
                else {
                    'MACHINE/WEBROOT/APPHOST'
                }
            }
            else {
                "IIS:\Sites\$website"
            }

            $task = [ordered] @{
                name = '{0} | {1} | Ensure {2} is set to {3} on section {4}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.Value, $rule.Key, $parsedConfigSection
                'ansible.windows.win_dsc' = [ordered] @{
                    'resource_name' = 'WebConfigProperty'
                    'WebsitePath' = $websitePath
                    'Filter' = $rule.ConfigSection
                    'PropertyName' = $rule.Key
                    'Value' = $rule.Value
                }
            }

            Write-Verbose "  Task: $($task.name)"

            if ($rule.Id -match '\.[a-z]$') {
                if ($null -ne $previousId -and $previousId -ne $baseId) {
                    $taskGroups[$previousId]
                }

                if (-not $taskGroups.ContainsKey($baseId)) {
                    $taskGroups[$baseId] = @{
                        $rule.Id = $baseId

                        Rule = $rule
                        Task = [ordered] @{
                            'name' = '{0} | {1} | Ensure section {2} is configured' -f $baseId, $rule.Severity.ToUpper(), $parsedConfigSection
                            'block' = [System.Collections.ArrayList]::new()
                            'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedConfigSection -Type Conditional -StigName $StigName
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
