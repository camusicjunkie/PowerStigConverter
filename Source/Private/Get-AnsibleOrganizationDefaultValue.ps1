function Get-AnsibleOrganizationDefaultValue {
    <#
    .SYNOPSIS
        The value one organization variable is declared with in defaults/.
    .DESCRIPTION
        Usually the org settings attribute verbatim. Two types need the value reshaped here
        rather than on the host, because the shape the ansible module consumes should be decided
        where a test can see it - see docs/adr/0003:

        a field the task needs as a list is split, so the variable holds a yaml sequence; and a
        certificate store path is reduced to its leaf, because PowerStig holds
        Cert:\LocalMachine\Root where win_certificate_info takes a store name of Root.

        Returns nothing when the setting is unanswered or missing, which is what declares the
        variable blank for the operator to fill in.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [object] $Node,

        [Parameter(Mandatory)]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $Field
    )

    $value = $Node.$Field
    if ([string]::IsNullOrWhiteSpace($value)) { return }

    if ($RuleType -eq 'RootCertificate' -and $Field -eq 'Location') {
        return Split-Path -Path $value -Leaf
    }

    if ($script:organizationData[$RuleType]['List'] -contains $Field) {
        return , ($value -split ',')
    }

    $value
}
