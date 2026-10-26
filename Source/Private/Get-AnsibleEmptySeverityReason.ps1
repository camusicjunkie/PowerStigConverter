function Get-AnsibleEmptySeverityReason {
    <#
    .SYNOPSIS
        The comment line an empty severity file and an empty toggle file both open with. See #133.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        $StigProfile,

        [Parameter(Mandatory)]
        [string] $Severity
    )

    '# No tasks were generated for {0} at {1} severity.' -f $StigProfile.StigName, $Severity
}
