<#
.SYNOPSIS
    Every name a generated role uses, and the defaults/ lines built on them.
.DESCRIPTION
    The declaration in defaults/, the reference a task interpolates and the assert that guards it
    all have to name the same variable, so they all come through here. See docs/adr/0003.

    These were one function taking a -Type, which meant a caller had to know which of TaskId,
    TaskName and NodeValue mattered for each of six values. See #16.
#>

<#
.SYNOPSIS
    The variable for one value of one rule - prefix_id_name. An organization variable, or a role
    variable the site fills in per rule.
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
    $name = Get-AnsibleVariableNameFragment -TaskName $TaskName

    '{0}_{1}_{2}' -f (Get-AnsibleVariablePrefix -StigName $StigName), $id, $name
}

<#
.SYNOPSIS
    A role variable every rule of a type shares - prefix_name - as one record.
.DESCRIPTION
    Name, Reference, Declaration and Assert together, so they cannot name different things; a
    generator returns the record as its RoleVariable. See #127 and docs/adr/0004. Declared once
    as an empty list every reading task loops over, and asserted non-empty because an empty list
    configures nothing (#57).
#>
function Get-AnsibleRoleVariable {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $StigName
    )

    $variable = '{0}_{1}' -f (Get-AnsibleVariablePrefix -StigName $StigName), (Get-AnsibleVariableNameFragment -TaskName $Name)

    [pscustomobject] @{
        Name = $variable
        Reference = '{0} {1} {2}' -f '{{', $variable, '}}'
        Declaration = '{0}: []' -f $variable
        Assert = [ordered] @{
            'name' = 'Assert {0} names something' -f $variable
            'ansible.builtin.assert' = [ordered] @{
                'that' = @('{0} | length > 0' -f $variable)
                'fail_msg' = '{0} is empty, so this role would configure nothing. Set it in defaults/main/main.yml or group_vars.' -f $variable
            }
        }
    }
}

<#
.SYNOPSIS
    A role variable the site fills in per rule - prefix_id_name - as the same record.
.DESCRIPTION
    Declared blank and not asserted; whether it should be is #128.
#>
function Get-AnsibleRuleVariable {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $TaskId,
        [Parameter(Mandatory)] [string] $StigName
    )

    $splat = @{ TaskId = $TaskId; TaskName = $Name; StigName = $StigName }

    [pscustomobject] @{
        Name = Get-AnsibleVariableName @splat
        Reference = Get-AnsibleVariableReference @splat
        Declaration = New-AnsibleVariableLine @splat
        Assert = $null
    }
}

<#
.SYNOPSIS
    A fact the generated tasks build up at run time - prefix_name.
.DESCRIPTION
    Named like a role-scoped variable but never declared in defaults/: it is the tasks' own
    running total, not a blank for the site to fill in.
#>
function Get-AnsibleFactName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $StigName
    )

    '{0}_{1}' -f (Get-AnsibleVariablePrefix -StigName $StigName), (Get-AnsibleVariableNameFragment -TaskName $Name)
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
    A task name as an ansible variable name fragment.
.DESCRIPTION
    Both the per-rule and the role-scoped name are built from one, so the mangling lives in one
    place the way the id's does.
#>
function Get-AnsibleVariableNameFragment {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TaskName
    )

    $TaskName.ToLower() -replace '\s', '_' -replace '[^\w]+'
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
    The defaults/ line declaring a severity toggle, on - prefix_category.
.DESCRIPTION
    tasks/main.yml guards each severity file's import on one, by category (cat1, cat2, cat3).
#>
function New-AnsibleSeverityToggleLine {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Category,
        [Parameter(Mandatory)] [string] $StigName
    )

    '{0}_{1}: true' -f (Get-AnsibleVariablePrefix -StigName $StigName), $Category
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
