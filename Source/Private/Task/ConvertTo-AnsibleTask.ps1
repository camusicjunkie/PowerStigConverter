function ConvertTo-AnsibleTask {
    <#
    .SYNOPSIS
        Turns rules of one rule type into task items, using that type's adapter for the part that
        differs.
    .DESCRIPTION
        Owns everything every rule type does the same way: the duplicate skip, resolving the
        organization value, naming, the conditional toggle, grouping sub-rules, attaching the
        assert and the shape handed on to the exporters.

        Build-Ansible<Type>Task supplies only what differs - the ansible module and the fields
        mapped into it. Nothing here branches on rule type; if it ever needs to, the adapter
        contract is the thing that is wrong.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{},

        [string] $StigId
    )

    begin {
        $adapter = 'Build-Ansible{0}Task' -f $RuleType
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        foreach ($rule in $InputObject) {
            # A duplicate is covered by the rule it points at.
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            # Guarded on the data, not on the type name - a rule type OrganizationData.psd1 says
            # nothing about has no organization value to resolve.
            $resolution = if ($script:organizationData.ContainsKey($RuleType)) {
                Resolve-AnsibleOrganizationValue -Rule $rule -RuleType $RuleType -StigName $StigName `
                    -OrganizationalSetting $OrganizationalSetting
            }

            $built = & $adapter -Rule $rule -StigName $StigName -StigId $StigId -Resolution $resolution
            if ($null -eq $built) { continue }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $severity = $rule.Severity.ToUpper()

            # An adapter names a task outright only where the generated role already did - the
            # members of a block a rule builds for itself. Everything else is prefixed.
            $tasks = @(foreach ($item in @($built.Task)) {
                $task = [ordered] @{
                    'name' = if ($item.Name) { $item.Name } else { '{0} | {1} | {2}' -f $rule.Id, $severity, $item.Detail }
                }
                foreach ($key in $item.Body.Keys) { $task[$key] = $item.Body[$key] }
                $task
            })

            # Sub-rules share a block so an operator switches the requirement off rather than one
            # of its halves; a rule that becomes several tasks needs one for the same reason.
            $group = $built.Group -or $rule.Id -match '\.[a-z]$' -or $tasks.Count -gt 1

            if (-not $group) {
                $task = $tasks[0]
                $task['when'] = Get-AnsibleToggleName -TaskId $rule.Id -StigName $StigName
                Write-Verbose "  Task: $($task.name)"

                $null = $items.Add(@{
                    Output = @{ Rule = $rule; Task = Add-AnsibleAssert -Task $task -Resolution $resolution }
                })
                continue
            }

            $groupTask = [ordered] @{
                'name' = '{0} | {1} | {2}' -f $baseId, $severity, $built.GroupDetail
                'block' = [System.Collections.ArrayList]::new()
                'when' = Get-AnsibleToggleName -TaskId $baseId -StigName $StigName
            }

            # One assert per rule, on the first task it produces - the one that consumes the value.
            # A rule that becomes a single task, which is all of them bar RootCertificate, gets the
            # same wrapping it would have got ungrouped.
            $first = $true
            foreach ($task in $tasks) {
                Write-Verbose "  Task: $($task.name)"

                $null = $items.Add(@{
                    GroupId = $baseId
                    Task = if ($first) { Add-AnsibleAssert -Task $task -Resolution $resolution } else { $task }
                    Output = @{ Rule = $rule; Task = $groupTask }
                })
                $first = $false
            }
        }
    }
    end {
        Group-AnsibleTask -InputObject $items.ToArray()
    }
}

<#
.SYNOPSIS
    Attaches the organization value assert, when there is a resolution and it has one.
#>
function Add-AnsibleAssert {
    param ($Task, $Resolution)

    if ($null -eq $Resolution) { return $Task }

    Add-AnsibleOrganizationValueAssert -Task $Task -Resolution $Resolution
}
