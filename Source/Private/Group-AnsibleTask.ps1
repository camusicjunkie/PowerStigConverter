function Group-AnsibleTask {
    [CmdletBinding()]
    param (
        # Items shaped @{ GroupId; Output; Task }.
        #
        # An item with no GroupId emits its Output unchanged. Items sharing a GroupId have
        # their Task appended to the block of the first Output seen for that id, and every
        # group is emitted once, in first-seen order, after all input is consumed.
        #
        # Items for a group do not have to arrive together.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    $taskGroups = [ordered] @{}

    foreach ($item in $InputObject) {
        if ([string]::IsNullOrEmpty($item.GroupId)) {
            $item.Output
            continue
        }

        if (-not $taskGroups.Contains($item.GroupId)) {
            $taskGroups[$item.GroupId] = $item.Output
            Write-Verbose "  TaskGroup: $($item.Output.Task.name)"
        }

        $null = $taskGroups[$item.GroupId].Task.block.Add($item.Task)
    }

    $taskGroups.Values
}
