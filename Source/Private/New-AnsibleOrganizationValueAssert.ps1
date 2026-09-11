function New-AnsibleOrganizationValueAssert {
    <#
    .SYNOPSIS
        Builds the assert that guards a rule whose organization values are still unanswered.
    .DESCRIPTION
        Emits nothing unless the org settings file leaves one of this rule's values for the
        organization to decide and nobody has decided it. New-AnsiblePlaybook normally refuses to
        generate at all in that case; this is what -AllowIncompleteOrganizationValue produces
        instead, so that a role generated over a part-filled org settings file fails loudly on the
        host rather than quietly setting an empty value. See docs/adr/0003.

        Only settings unanswered at generation time get one, so the asserts in a role double as
        the list of questions nobody answered, and they disappear when it is regenerated against a
        filled-in org settings file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        [Parameter(Mandatory)]
        [ValidateSet('AccountPolicy', 'IisLogging', 'Registry', 'RootCertificate', 'SecurityOption', 'Service', 'UserRight')]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrgSetting = @{}
    )

    $gaps = @(Get-AnsibleOrganizationValueGap -Rule $Rule -RuleType $RuleType -OrgSetting $OrgSetting)
    if ($gaps.Count -eq 0) { return }

    $variables = foreach ($gap in $gaps) {
        Get-AnsibleOrganizationVariableName -Rule $Rule -RuleType $RuleType -Field $gap.Field -StigName $StigName
    }

    [ordered] @{
        'name' = 'Assert the organization values for {0} have been filled in' -f $Rule.Id
        'ansible.builtin.assert' = [ordered] @{
            # default("", true) so an undefined variable fails the assert rather than the play.
            'that' = @($variables | ForEach-Object { '{0} | default("", true) | length > 0' -f $_ })
            'fail_msg' = '{0} needs {1} set in defaults/main/main_default_org.yml - PowerStig leaves this value for the organization to decide.' -f $Rule.Id, ($variables -join ', ')
        }
    }
}
