function Group-AnsibleRuleBySeverity {
    [CmdletBinding()]
    param (
        # Items shaped @{ Id; Severity; Value }. The first item for a given Id wins and later
        # duplicates are discarded. Items whose Severity is not high, medium or low are dropped.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    $bySeverity = [ordered] @{
        high = [System.Collections.SortedList]::new()
        medium = [System.Collections.SortedList]::new()
        low = [System.Collections.SortedList]::new()
    }

    foreach ($item in $InputObject) {
        if (-not $bySeverity.Contains($item.Severity)) { continue }
        if ($bySeverity[$item.Severity].ContainsKey($item.Id)) { continue }

        $bySeverity[$item.Severity].Add($item.Id, $item.Value)
    }

    $bySeverity
}
