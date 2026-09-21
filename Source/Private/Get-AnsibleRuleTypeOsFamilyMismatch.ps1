function Get-AnsibleRuleTypeOsFamilyMismatch {
    <#
    .SYNOPSIS
        The OsFamily a rule type's adapter targets, when it disagrees with the conversion's own -
        or $null when it agrees, or RuleTypeOsFamily.psd1 says nothing about it either way.
    .DESCRIPTION
        The one place every caller that cares whether a rule type applies to this conversion's
        OsFamily asks the question, rather than each reading RuleTypeOsFamily.psd1 for itself -
        dispatch, the incomplete-organization-value gate and the organization value exporter all
        call this. See docs/adr/0010, docs/adr/0011.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $OsFamily
    )

    $adapterOsFamily = $script:ruleTypeOsFamily[$RuleType]
    if ($adapterOsFamily -and $adapterOsFamily -ne $OsFamily) {
        return $adapterOsFamily
    }

    $null
}
