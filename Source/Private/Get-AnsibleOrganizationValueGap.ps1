function Get-AnsibleOrganizationValueGap {
    <#
    .SYNOPSIS
        Reports the organization values a rule needs but the org settings file does not answer.
    .DESCRIPTION
        DISA leaves some values to the adopting organization, and PowerStig ships those settings
        blank. A blank one is an outstanding decision rather than a data error, so the conversion
        refuses to produce a role until it is answered - see docs/adr/0001.

        Two faults are reported, because their remedies differ. A missing setting means the org
        settings file carries no entry for the rule at all, which usually means it does not match
        the STIG version in hand; the operator fetches the right file. An unanswered setting means
        the entry is there and empty; the operator fills it in.

        Rules that produce no task raise no gap: a duplicate is covered by the rule it points at,
        and a rule that does not require an organization value carries its value inline.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        [Parameter(Mandatory)]
        [ValidateSet('AccountPolicy', 'IisLogging', 'Registry', 'RootCertificate', 'SecurityOption', 'Service', 'UserRight')]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [hashtable] $OrgSetting
    )

    if ($Rule.OrganizationValueRequired -ne $true) { return }
    if (-not [string]::IsNullOrEmpty($Rule.DuplicateOf)) { return }

    $node = $OrgSetting[$Rule.Id]

    # One gap per field either way, so Field is always a single field name. Reporting a missing
    # node as one gap naming every field at once meant the caller had to split that list apart
    # again to name the variables it guards.
    foreach ($field in $script:organizationData[$RuleType]['Required']) {
        if ($null -eq $node) {
            [pscustomobject] @{
                RuleId = $Rule.Id
                RuleType = $RuleType
                Field = $field
                Reason = 'Missing'
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($node.$field)) {
            [pscustomobject] @{
                RuleId = $Rule.Id
                RuleType = $RuleType
                Field = $field
                Reason = 'Unanswered'
            }
        }
    }
}
