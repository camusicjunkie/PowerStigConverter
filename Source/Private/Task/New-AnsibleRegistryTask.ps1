function New-AnsibleRegistryTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{}
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ TaskId = $rule.Id; TaskName = $rule.ValueName; StigName = $StigName }

            $organizationValue = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType 'Registry' -StigName $StigName -OrganizationalSetting $OrganizationalSetting
            $valueData = $organizationValue.Value
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
                $groupTask = [ordered] @{
                    'name' = '{0} | {1} | {2}' -f $baseId, $rule.Severity.ToUpper(), $parsedValueName
                    'block' = [System.Collections.ArrayList]::new()
                    'when' = New-AnsibleVariable -TaskId $baseId -TaskName $parsedValueName -Type Conditional -StigName $StigName
                }

                $item = @{
                    GroupId = $baseId
                    Task = Add-AnsibleOrganizationValueAssert -Task $task -OrganizationValue $organizationValue
                    Output = @{
                        Rule = $rule
                        Name = $parsedValueName
                        Task = $groupTask
                    }
                }
            }
            else {
                $task.when = New-AnsibleVariable @navParams -Type Conditional

                $item = @{
                    Output = @{
                        Rule = $rule
                        Task = Add-AnsibleOrganizationValueAssert -Task $task -OrganizationValue $organizationValue
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
