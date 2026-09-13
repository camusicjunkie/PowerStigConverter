<#
.SYNOPSIS
    The IIS configuration a task acts on - machine-wide, or every site the role names.
.DESCRIPTION
    A server STIG configures the machine-wide path a caller already knows how to build for its
    own resource; a site STIG describes a hardened website, so its rules configure every site the
    role names rather than one the operator picks per rule. That makes the site branch a loop
    rather than a scalar path, which is why this returns an object: the path, the list to loop
    over, and the role variable that list comes from.

    Shared by every IIS task generator so the site-vs-machine decision, and the site reference,
    can't diverge between them the way MimeType and WebConfigurationProperty once did - and so a
    future rule type cannot get the path right and the loop wrong. See #57.
#>
function Get-AnsibleIisScope {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string] $StigId,
        [Parameter(Mandatory)] [string] $MachinePath,
        [Parameter(Mandatory)] [string] $StigName
    )

    if ($StigId -match 'IIS_.+_Server') {
        return @{ Path = $MachinePath }
    }

    @{
        # item is the site name the loop is on, so the path is the same string for every site.
        Path = 'IIS:\Sites\{{ item }}'
        Loop = Get-AnsibleRoleVariableReference -TaskName 'websites' -StigName $StigName
        RoleVariable = 'websites'
    }
}
