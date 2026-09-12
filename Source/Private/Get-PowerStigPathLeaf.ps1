<#
.SYNOPSIS
    The last '/'-delimited segment of a PowerStig field value.
.DESCRIPTION
    PowerStig always writes ConfigSection and MimeType forward-slash-delimited, regardless of
    the converting machine's platform, so the leaf is taken by matching that literal character
    rather than through Split-Path - whose separator comes from the current provider/platform,
    returns the parent segment rather than the leaf without -Leaf, and would leave the value
    unsplit on a platform that doesn't treat '/' as a path separator. Shared by
    Build-AnsibleMimeTypeTask and Build-AnsibleWebConfigurationPropertyTask so the two can't
    diverge the way #49 found them already had.
#>
function Get-PowerStigPathLeaf {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Path
    )

    $Path.Substring($Path.LastIndexOf('/') + 1)
}
