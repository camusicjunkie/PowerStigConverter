function Group-AnsibleBySeverity {
    <#
    .SYNOPSIS
        Sorts items into the three DISA categories the role splits its files by - where the
        generator maps high, medium and low to cat1, cat2 and cat3. See #130.
    .OUTPUTS
        An ordered map cat1, cat2, cat3, every one present however few items there are. Each
        carries its Severity and its Item values, ordered by id so generated files are stable,
        after any item marked First (#232).
    #>
    [CmdletBinding()]
    param (
        # Items shaped @{ Id; Severity; Value; First }. A repeated id keeps its first value; a
        # severity outside the three has no file and is dropped.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    $severities = @(@('cat1', 'high'), @('cat2', 'medium'), @('cat3', 'low'))
    $bucket = @{}
    foreach ($entry in $severities) {
        $bucket[$entry[1]] = @{ $true = [System.Collections.SortedList]::new(); $false = [System.Collections.SortedList]::new() }
    }

    foreach ($item in $InputObject) {
        $lists = if ($item.Severity) { $bucket[$item.Severity] }
        if ($null -eq $lists -or $lists[$true].ContainsKey($item.Id) -or $lists[$false].ContainsKey($item.Id)) { continue }

        $lists[[bool] $item.First].Add($item.Id, $item.Value)
    }

    $category = [ordered] @{}
    foreach ($entry in $severities) {
        $items = [ordered] @{}
        foreach ($first in $true, $false) {
            foreach ($pair in $bucket[$entry[1]][$first].GetEnumerator()) { $items[$pair.Key] = $pair.Value }
        }
        $category[$entry[0]] = [pscustomobject] @{ Severity = $entry[1]; Item = $items }
    }

    $category
}
