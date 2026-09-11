function New-AnsibleWebConfigurationPropertyTask {
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
                $groupTask = [ordered] @{
                    'name' = '{0} | {1} | Ensure section {2} is configured' -f $baseId, $rule.Severity.ToUpper(), $parsedConfigSection
                    'block' = [System.Collections.ArrayList]::new()
                    'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedConfigSection -Type Conditional -StigName $StigName
                }

                $item = @{
                    GroupId = $baseId
                    Task = $task
                    Output = @{
                        Rule = $rule
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
