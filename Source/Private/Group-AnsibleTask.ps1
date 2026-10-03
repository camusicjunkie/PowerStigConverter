function Group-AnsibleTask {
    [CmdletBinding()]
    param (
        # Items shaped @{ GroupId; Output; Task }.
        #
        # An item with no GroupId emits its Output unchanged. Items sharing a GroupId have
        # their Task appended to the block of the first Output seen for that id, and every
        # group is emitted once, in first-seen order, after all input is consumed.
        #
        # Items for a group do not have to arrive together. Each member's handlers, role variables,
        # declarations and unanswered values are combined into the emitted Output, not dropped.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    $taskGroups = [ordered] @{}
    $combined = 'Handler', 'RoleVariable', 'Declaration', 'Incomplete'

    foreach ($item in $InputObject) {
        if ([string]::IsNullOrEmpty($item.GroupId)) {
            $item.Output
            continue
        }

        if (-not $taskGroups.Contains($item.GroupId)) {
            $taskGroups[$item.GroupId] = $item.Output.Clone()
            Write-Verbose "  TaskGroup: $($item.Output.Task.name)"
        }
        else {
            $kept = $taskGroups[$item.GroupId]
            foreach ($key in $combined) {
                $kept[$key] = @(@($kept[$key]) + @($item.Output[$key]) | Where-Object { $null -ne $_ })
            }
        }

        $null = $taskGroups[$item.GroupId].Task.block.Add($item.Task)
    }

    $taskGroups.Values
}
