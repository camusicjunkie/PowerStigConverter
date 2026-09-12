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

    $id = Get-AnsibleVariableIdFragment -TaskId $TaskId
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

    $id = Get-AnsibleVariableIdFragment -TaskId $TaskId

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

<#
.SYNOPSIS
    The rule id as an ansible variable name fragment.
.DESCRIPTION
    Every name here is built from one, so the mangling lives in one place. A sub-rule id carries
    a suffix (V-254343.b) that no ansible variable name may contain.
#>
function Get-AnsibleVariableIdFragment {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId
    )

    $TaskId -replace 'V-' -replace '[^A-Za-z0-9]+', '_'
}

<#
.SYNOPSIS
    The variable a gather task registers its result in - prefix_id_suffix.
.DESCRIPTION
    Named from the rule rather than from what is being gathered, because the service or
    certificate name may be an organization variable reference by the time the task is built.
#>
function Get-AnsibleRegisterName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [string] $StigName,
        [Parameter(Mandatory)] [string] $Suffix
    )

    '{0}_{1}_{2}' -f (Get-AnsibleVariablePrefix -StigName $StigName),
        (Get-AnsibleVariableIdFragment -TaskId $TaskId), $Suffix
}
