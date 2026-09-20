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

            $baseId = Get-PowerStigBaseRuleId -Id $rule.Id
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

            # A generator names the role variables its tasks reference - the sites or app pools
            # the implementing site fills in. Carried through without branching on rule type, the
            # way the handler is: this is the single source for the reference, the defaults/
            # declaration and the assert guarding it. See #57.
            $roleVariables = @($built.RoleVariable | Where-Object { $_ })

            # A rule type that cannot be expressed as one task per rule returns a handler as
            # well - the single write several rules notify. It is named outright because notify
            # addresses it by name, and takes neither toggle nor assert: those guard the rule's
            # own task, which is the thing that notifies.
            $handlers = @(foreach ($item in @($built.Handler)) {
                if ($null -eq $item) { continue }

                $handler = [ordered] @{ 'name' = $item.Name }
                foreach ($key in $item.Body.Keys) { $handler[$key] = $item.Body[$key] }
                $handler
            })

            # Sub-rules share a block so an operator switches the requirement off rather than one
            # of its halves; a rule that becomes several tasks needs one for the same reason.
            $group = $built.Group -or (Test-PowerStigSubRuleId -Id $rule.Id) -or $tasks.Count -gt 1

            if (-not $group) {
                $task = $tasks[0]
                $task['when'] = Get-AnsibleToggleName -TaskId $rule.Id -StigName $StigName
                Write-Verbose "  Task: $($task.name)"

                $null = $items.Add(@{
                    Output = @{
                        Rule = $rule
                        Task = Add-AnsibleAssert -Task $task -Resolution $resolution
                        Handler = $handlers
                        RoleVariable = $roleVariables
                    }
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
                    BaseId = $baseId
                    Severity = $severity
                    GroupDetail = $built.GroupDetail
                    Task = if ($first) { Add-AnsibleAssert -Task $task -Resolution $resolution } else { $task }
                    Output = @{ Rule = $rule; Task = $groupTask; Handler = $handlers; RoleVariable = $roleVariables }
                })
                $first = $false
            }
        }
    }
    end {
        Set-AnsibleGroupTaskName -Item $items
        Group-AnsibleTask -InputObject $items.ToArray()
    }
}

<#
.SYNOPSIS
    Widens a group's name to every distinct GroupDetail its sub-rules produced, not only the one
    Group-AnsibleTask happens to keep.
.DESCRIPTION
    Every sub-rule builds its own $groupTask instance up front, all sharing one GroupId;
    Group-AnsibleTask keeps only the first one it sees and appends the rest into its block. That
    is the right behaviour for a rule type where every sub-rule's GroupDetail is already the
    same string (every generator before nxFileLine), but nxFileLine's sub-rules can each touch a
    different file - see ADR 0009. So this runs first, in id-appearance order, and rewrites every
    surviving group task's name from the union - a no-op wherever the values already agreed.
#>
function Set-AnsibleGroupTaskName {
    param ([System.Collections.ArrayList] $Item)

    $detail = [ordered] @{}
    foreach ($entry in $Item) {
        if ([string]::IsNullOrEmpty($entry.GroupId)) { continue }

        if (-not $detail.Contains($entry.GroupId)) {
            $detail[$entry.GroupId] = [System.Collections.Generic.List[string]]::new()
        }
        if ($entry.GroupDetail -and -not $detail[$entry.GroupId].Contains($entry.GroupDetail)) {
            $detail[$entry.GroupId].Add($entry.GroupDetail)
        }
    }

    foreach ($entry in $Item) {
        if ([string]::IsNullOrEmpty($entry.GroupId)) { continue }

        $entry.Output.Task.name = '{0} | {1} | {2}' -f $entry.BaseId, $entry.Severity, ($detail[$entry.GroupId] -join ', ')
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
