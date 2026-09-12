<#
.SYNOPSIS
    The names every generated variable is built from, and the four things built on them.
.DESCRIPTION
    The declaration in defaults/, the reference a task interpolates and the assert that guards it
    all have to name the same variable, so they all come through here. See docs/adr/0003.

    These were one function taking a -Type, which meant a caller had to know which of TaskId,
    TaskName and NodeValue mattered for each of six values. See #16.
#>

<#
.SYNOPSIS
    The organization variable for one value of one rule - prefix_id_name.
#>
function Get-AnsibleVariableName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TaskName,
        [Parameter(Mandatory)] [string] $StigName
    )

    # Sub-rule ids carry a suffix (V-254343.b) that is not legal in an ansible variable name.
    $id = $TaskId -replace 'V-' -replace '[^A-Za-z0-9]+', '_'
    $name = $TaskName.ToLower() -replace '\s', '_' -replace '[^\w]+'

    '{0}_{1}_{2}' -f (Get-AnsibleVariablePrefix -StigName $StigName), $id, $name
}

<#
.SYNOPSIS
    The jinja reference a task interpolates in place of a literal value.
#>
function Get-AnsibleVariableReference {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TaskName,
        [Parameter(Mandatory)] [string] $StigName
    )

    '{0} {1} {2}' -f '{{', (Get-AnsibleVariableName @PSBoundParameters), '}}'
}

<#
.SYNOPSIS
    The defaults/ line declaring an organization variable with its value.
#>
function New-AnsibleVariableLine {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TaskName,
        [Parameter(Mandatory)] [string] $StigName,
        [Parameter()] [object] $NodeValue
    )

    # A value the task needs as a list is split before it gets here and is written as a yaml flow
    # sequence, so the whole variable can be interpolated as one. See docs/adr/0003.
    $quoted = if ($NodeValue -is [array]) {
        '[{0}]' -f (($NodeValue | ForEach-Object { Format-AnsibleYamlScalar -Value $_ -InSequence }) -join ', ')
    }
    else {
        Format-AnsibleYamlScalar -Value $NodeValue
    }

    '{0}: {1}' -f (Get-AnsibleVariableName -TaskId $TaskId -TaskName $TaskName -StigName $StigName), $quoted
}

<#
.SYNOPSIS
    The conditional toggle guarding one generated rule - prefix_id_when.
.DESCRIPTION
    Named from the rule id alone. A toggle switches a whole requirement off, so a sub-rule takes
    its base id and there is nothing for a task name to contribute.
#>
function Get-AnsibleToggleName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [string] $StigName
    )

    $id = $TaskId -replace 'V-' -replace '[^A-Za-z0-9]+', '_'

    '{0}_{1}_when' -f (Get-AnsibleVariablePrefix -StigName $StigName), $id
}

<#
.SYNOPSIS
    The defaults/ line declaring a conditional toggle, on.
#>
function New-AnsibleToggleLine {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [string] $StigName
    )

    '{0}: true' -f (Get-AnsibleToggleName @PSBoundParameters)
}
