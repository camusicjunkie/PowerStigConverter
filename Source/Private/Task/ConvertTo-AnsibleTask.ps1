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
    Names every surviving group task from the strongest thing its sub-rules agree on, not from
    whichever one Group-AnsibleTask happens to keep.
.DESCRIPTION
    Every sub-rule builds its own $groupTask instance up front, all sharing one GroupId;
    Group-AnsibleTask keeps only the first one it sees and appends the rest into its block, so
    the name it keeps describes one half of a requirement rather than the whole of it. This runs
    first, in id-appearance order, and rewrites the name.

    A generator offers its GroupDetail as the candidates its sub-rules might agree on, strongest
    first; Get-AnsibleBlockDetail picks the first one they all do agree on, and unions when they
    agree on none. A generator with nothing to prefer offers a single candidate - a bare string -
    and gets the union it always got. See ADR 0015.
#>
function Set-AnsibleGroupTaskName {
    param ([System.Collections.ArrayList] $Item)

    $candidate = [ordered] @{}
    foreach ($entry in $Item) {
        if ([string]::IsNullOrEmpty($entry.GroupId)) { continue }

        if (-not $candidate.Contains($entry.GroupId)) {
            $candidate[$entry.GroupId] = [System.Collections.Generic.List[object]]::new()
        }
        $candidate[$entry.GroupId].Add(@($entry.GroupDetail))
    }

    $detail = [ordered] @{}
    foreach ($groupId in $candidate.Keys) {
        $detail[$groupId] = Get-AnsibleBlockDetail -Candidate $candidate[$groupId]
    }

    foreach ($entry in $Item) {
        if ([string]::IsNullOrEmpty($entry.GroupId)) { continue }

        $entry.Output.Task.name = '{0} | {1} | {2}' -f $entry.BaseId, $entry.Severity, $detail[$entry.GroupId]
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

<#
.SYNOPSIS
    Attaches the organization value assert, when there is a resolution and it has one.
#>
function Add-AnsibleAssert {
    param ($Task, $Resolution)

    if ($null -eq $Resolution) { return $Task }

    Add-AnsibleOrganizationValueAssert -Task $Task -Resolution $Resolution
}
