function Get-AnsibleOrganizationTaskName {
    <#
    .SYNOPSIS
        The name part of the defaults/ variable carrying one organization value field.
    .DESCRIPTION
        Rule types with a Name property - a policy name, a value name, the display name of a
        user right - name the variable after it, because one such type carries a single value
        and the rule's own word for it reads better than the org node's attribute name. The
        types whose task needs several fields have no single such name, so each variable is
        named for its field instead.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        [Parameter(Mandatory)]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $Field
    )

    $orgName = $script:organizationData[$RuleType]['Name']
    if ([string]::IsNullOrEmpty($orgName)) { $Field } else { $Rule.$orgName }
}
