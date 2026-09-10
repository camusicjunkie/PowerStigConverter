function Test-PowerStigOrgValue {
    [CmdletBinding()]
    param (
        [string] $NodeValue,

        [string] $RuleId
    )

    $populated = $false
    if ([string]::IsNullOrEmpty($NodeValue)) {
        $populated = $true
        Write-Warning ("Validate the org settings xml is properly filled out for {0}." -f $RuleId)
    }
    $populated
}
