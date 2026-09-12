<#
.SYNOPSIS
    The sub-rule id convention, in the one place it is written down.
.DESCRIPTION
    A sub-rule is a STIG rule whose id carries a letter suffix (V-254343.b) because one
    requirement needs several tasks. Generators, the exporter and the task adapter all ask about
    it; before #18 they each restated the regex. See CONTEXT.md for the term.
#>

<#
.SYNOPSIS
    Whether a rule id carries a sub-rule suffix.
#>
function Test-PowerStigSubRuleId {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [string] $Id
    )

    # Asked of the base id rather than of a second copy of the regex, so the convention is
    # written down once.
    (Get-PowerStigBaseRuleId -Id $Id) -ne $Id
}

<#
.SYNOPSIS
    The id a sub-rule belongs to - an id with no suffix comes back unchanged.
#>
function Get-PowerStigBaseRuleId {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Id
    )

    $Id -replace '\.[a-z]$'
}
