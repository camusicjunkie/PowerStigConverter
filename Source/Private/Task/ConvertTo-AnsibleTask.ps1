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
        $converted = [System.Collections.ArrayList]::new()
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

            # What this rule declares in defaults/ and leaves unanswered - carried on its output, so
            # only a rule that produced a task can declare or refuse. See docs/adr/0016.
            $declaration = @(@(
                $resolution.Variable.Declaration
                # The IIS log path: a per-rule role variable no resolution feeds.
                if ($script:roleVariableData.ContainsKey($RuleType)) {
                    foreach ($taskName in $script:roleVariableData[$RuleType].PerRule) {
                        New-AnsibleVariableLine -TaskId $rule.Id -TaskName $taskName -StigName $StigName
                    }
                }
            ) | Where-Object { $_ })
            $incomplete = @($resolution.Incomplete | Where-Object { $_ })

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

            foreach ($task in $tasks) { Write-Verbose "  Task: $($task.name)" }

            # Sub-rules share a block so an operator switches the requirement off rather than one
            # of its halves; a rule that becomes several tasks needs one for the same reason.
            $group = $built.Group -or (Test-PowerStigSubRuleId -Id $rule.Id) -or $tasks.Count -gt 1

            # A rule of its own is toggled on its task, before the assert wraps it and takes the
            # toggle along. One assert per rule, on its first task - the one that consumes the value.
            if (-not $group) { $tasks[0]['when'] = Get-AnsibleToggleName -TaskId $rule.Id -StigName $StigName }
            if ($resolution) { $tasks[0] = Add-AnsibleOrganizationValueAssert -Task $tasks[0] -Resolution $resolution }

            $null = $converted.Add([pscustomobject] @{
                Rule = $rule
                BaseId = $baseId
                Severity = $severity
                GroupDetail = $built.GroupDetail
                Task = $tasks
                Group = $group
                # What the rule hands on beside its task, combined across a block.
                Carried = @{ Handler = $handlers; RoleVariable = $roleVariables; Declaration = $declaration; Incomplete = $incomplete }
            })
        }
    }
    end {
        Merge-AnsibleRequirement -Converted $converted -StigName $StigName
    }
}

<#
.SYNOPSIS
    One output per requirement: a rule's own task, or one block for every sub-rule sharing a base
    id, in the order the requirements first appear.
.DESCRIPTION
    A block is named, filled, toggled and handed what every member carries in one place, so no
    member's handlers, role variables, declarations or unanswered values are lost. A rule of its
    own is the one-member case and passes through. See #125 and ADR 0015.
#>
function Merge-AnsibleRequirement {
    param ([System.Collections.ArrayList] $Converted, [string] $StigName)

    $requirements = [System.Collections.Generic.List[object]]::new()
    $blocks = @{}
    foreach ($record in $Converted) {
        if (-not $record.Group) { $requirements.Add(@($record)); continue }

        if (-not $blocks.ContainsKey($record.BaseId)) {
            $blocks[$record.BaseId] = [System.Collections.Generic.List[object]]::new()
            $requirements.Add($blocks[$record.BaseId])
        }
        $blocks[$record.BaseId].Add($record)
    }

    foreach ($members in $requirements) {
        $first = $members[0]
        $output = @{ Rule = $first.Rule }
        # Flattened by hand: member enumeration over one member hands back its empty array whole.
        foreach ($key in $first.Carried.Keys) {
            $output[$key] = @(foreach ($member in $members) { foreach ($value in $member.Carried[$key]) { $value } })
        }

        if (-not $first.Group) {
            $output.Task = $first.Task[0]
            $output
            continue
        }

        $candidate = [System.Collections.Generic.List[object]]::new()
        foreach ($member in $members) { $candidate.Add(@($member.GroupDetail)) }

        $output.Task = [ordered] @{
            'name' = '{0} | {1} | {2}' -f $first.BaseId, $first.Severity, (Get-AnsibleBlockDetail -Candidate $candidate)
            'block' = @(foreach ($member in $members) { $member.Task })
            'when' = Get-AnsibleToggleName -TaskId $first.BaseId -StigName $StigName
        }
        Write-Verbose "  TaskGroup: $($output.Task.name)"
        $output
    }
}

<#
.SYNOPSIS
    The block detail for one group: the strongest candidate its members agree on, else the union
    of their strongest.
.DESCRIPTION
    One candidate list per member of the group, each ordered strongest first. A candidate counts
    as agreed only when every member offers one at that rank and all of them are equal - a member
    offering fewer candidates than another cannot agree at a rank it does not reach.

    Falling through to the union is what a group whose members agree on nothing gets, and what a
    rule type offering one candidate always gets: the distinct strongest candidates, in the order
    the members appear. See ADR 0015.
#>
function Get-AnsibleBlockDetail {
    param ([System.Collections.Generic.List[object]] $Candidate)

    $rank = ($Candidate | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    for ($i = 0; $i -lt $rank; $i++) {
        $atRank = @($Candidate | ForEach-Object { $_[$i] })
        if (@($atRank | Where-Object { [string]::IsNullOrEmpty($_) }).Count -gt 0) { continue }
        if (@($atRank | Sort-Object -Unique).Count -eq 1) { return $atRank[0] }
    }

    $union = [System.Collections.Generic.List[string]]::new()
    foreach ($list in $Candidate) {
        if ([string]::IsNullOrEmpty($list[0]) -or $union.Contains($list[0])) { continue }
        $union.Add($list[0])
    }

    $union -join ', '
}
