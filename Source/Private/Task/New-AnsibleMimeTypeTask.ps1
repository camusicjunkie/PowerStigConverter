function New-AnsibleMimeTypeTask {
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

            $parsedMimeType = if ($rule.Id -match '\.[a-z]$') { Split-Path -Path $rule.MimeType } else { $rule.MimeType }
            $website = '' # this needs to be defined for iis site stig
            $configurationPath = if ($StigId -match 'IIS_.+_Server') { 'MACHINE/WEBROOT/APPHOST' } else { "IIS:\Sites\$website" }

            $task = [ordered] @{
                name = '{0} | {1} | Ensure {2} for {3} is {4}' -f $rule.Id, $rule.Severity.ToUpper(), $rule.Extension, $rule.MimeType, $rule.Ensure
                'ansible.windows.win_dsc' = [ordered] @{
                    'resource_name' = 'IISMimeTypeMapping'
                    'ConfigurationPath' = $configurationPath
                    'Extension' = $rule.Extension
                    'MimeType' = $rule.MimeType
                    'Ensure' = $rule.Ensure
                }
            }

            Write-Verbose "  Task: $($task.name)"

            if ($rule.Id -match '\.[a-z]$') {
                if ($null -ne $previousId -and $previousId -ne $baseId) {
                    $taskGroups[$previousId]
                }

                if (-not $taskGroups.ContainsKey($baseId)) {
                    $taskGroups[$baseId] = @{
                        Rule = @{
                            Id = $baseId
                            Severity = $rule.Severity
                            OrganizationValueRequired = $rule.OrganizationValueRequired
                        }
                        Name = $parsedMimeType
                        Task = [ordered] @{
                            'name' = '{0} | {1} | Ensure {2} MIME types are set' -f $baseId, $rule.Severity.ToUpper(), $parsedMimeType
                            'block' = [System.Collections.ArrayList]::new()
                            'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedMimeType -Type Conditional -StigName $StigName
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
