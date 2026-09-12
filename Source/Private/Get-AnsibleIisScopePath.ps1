<#
.SYNOPSIS
    The IIS configuration path a task acts on - machine-wide, or one site.
.DESCRIPTION
    A server STIG configures the machine-wide path a caller already knows how to build for its
    own resource; a site STIG instead targets one site, whose name the implementing site fills in
    as a variable. Shared by every IIS task generator so the site-vs-machine decision, and the
    site reference, can't diverge between them the way MimeType and WebConfigurationProperty once did.
#>
function Get-AnsibleIisScopePath {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $StigId,
        [Parameter(Mandatory)] [string] $MachinePath,
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [string] $StigName
    )

    if ($StigId -match 'IIS_.+_Server') {
        $MachinePath
    }
    else {
        $website = Get-AnsibleVariableReference -TaskId $TaskId -TaskName 'website' -StigName $StigName
        "IIS:\Sites\$website"
    }
}
