function New-AnsibleMimeTypeTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{},

        [string] $StigId
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

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
                $groupTask = [ordered] @{
                    'name' = '{0} | {1} | Ensure {2} MIME types are set' -f $baseId, $rule.Severity.ToUpper(), $parsedMimeType
                    'block' = [System.Collections.ArrayList]::new()
                    'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedMimeType -Type Conditional -StigName $StigName
                }

                $item = @{
                    GroupId = $baseId
                    Task = $task
                    Output = @{
                        Rule = @{
                            Id = $baseId
                            Severity = $rule.Severity
                            OrganizationValueRequired = $rule.OrganizationValueRequired
                        }
                        Name = $parsedMimeType
                        Task = $groupTask
                    }
                }
            }
            else {
                $task.when = New-AnsibleVariable @navParams -Type Conditional

                $item = @{
                    Output = @{
                        Rule = $rule
                        Task = $task
                    }
                }
            }

            $null = $items.Add($item)
        }
    }
    end {
        Group-AnsibleTask -InputObject $items.ToArray()
    }
}
