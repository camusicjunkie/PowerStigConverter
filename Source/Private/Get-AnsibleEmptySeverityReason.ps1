function Get-AnsibleEmptySeverityReason {
    <#
    .SYNOPSIS
        The comment line an empty severity file and an empty toggle file both open with. See #133.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string] $StigName,

        [Parameter(Mandatory)]
        [string] $Severity
    )

    '# {0} has no {1} severity rules.' -f $StigName, $Severity
}
