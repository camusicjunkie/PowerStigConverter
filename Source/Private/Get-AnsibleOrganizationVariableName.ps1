function Get-AnsibleOrganizationVariableName {
    <#
    .SYNOPSIS
        Names the defaults/ variable that carries one organization value field.
    .DESCRIPTION
        The declaration in defaults/, the reference the task interpolates and the assert that
        guards it must all name the same variable. They all come through here so they cannot
        drift apart.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        [Parameter(Mandatory)]
        [ValidateSet('AccountPolicy', 'IisLogging', 'Registry', 'RootCertificate', 'SecurityOption', 'Service', 'UserRight')]
        [string] $RuleType,

        [Parameter(Mandatory)]
        [string] $Field,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    $taskName = Get-AnsibleOrganizationTaskName -Rule $Rule -RuleType $RuleType -Field $Field

    New-AnsibleVariable -TaskId $Rule.Id -TaskName $taskName -StigName $StigName -Type OrganizationName
}
