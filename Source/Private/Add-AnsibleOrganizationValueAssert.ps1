function Add-AnsibleOrganizationValueAssert {
    <#
    .SYNOPSIS
        Wraps a task in a block guarded by an assert, when its organization values are unanswered.
    .DESCRIPTION
        Returns the task untouched when there is nothing to guard, which is the usual case: the
        conversion refuses outright unless -AllowIncompleteOrganizationValue was passed.

        The assert has to go inside the rule's own task rather than beside it, because tasks are
        keyed by rule id on the way to the severity file and only the first task for an id
        survives.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Task,

        [Parameter(Mandatory)]
        [object] $Rule,

        [Parameter(Mandatory)]
        [ValidateSet('AccountPolicy', 'IisLogging', 'Registry', 'RootCertificate', 'SecurityOption', 'Service', 'UserRight')]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrgSetting = @{}
    )

    $assert = New-AnsibleOrganizationValueAssert -Rule $Rule -RuleType $RuleType -StigName $StigName -OrgSetting $OrgSetting
    if ($null -eq $assert) { return $Task }

    $block = [ordered] @{
        'name' = $Task.name
        'block' = @($assert, $Task)
    }
    if ($Task.Contains('when')) { $block['when'] = $Task['when'] }

    $block
}
