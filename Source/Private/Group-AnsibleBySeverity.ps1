function Group-AnsibleBySeverity {
    <#
    .SYNOPSIS
        Sorts items into the three DISA categories the role splits its files by - where the
        generator maps high, medium and low to cat1, cat2 and cat3. See #130.
    .OUTPUTS
        An ordered map cat1, cat2, cat3, every one present however few items there are. Each
        carries its Severity and its Item values, ordered by id so generated files are stable.
    #>
    [CmdletBinding()]
    param (
        # Items shaped @{ Id; Severity; Value }. A repeated id keeps its first value; a severity
        # outside the three has no file and is dropped.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    $category = [ordered] @{}
    $bySeverity = @{}
    foreach ($entry in @(@('cat1', 'high'), @('cat2', 'medium'), @('cat3', 'low'))) {
        $category[$entry[0]] = [pscustomobject] @{ Severity = $entry[1]; Item = [System.Collections.SortedList]::new() }
        $bySeverity[$entry[1]] = $category[$entry[0]].Item
    }

    foreach ($item in $InputObject) {
        $bucket = if ($item.Severity) { $bySeverity[$item.Severity] }
        if ($null -eq $bucket -or $bucket.ContainsKey($item.Id)) { continue }

        $bucket.Add($item.Id, $item.Value)
    }

    $category
}
