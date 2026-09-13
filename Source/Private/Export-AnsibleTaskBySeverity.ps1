function Export-AnsibleTaskBySeverity {
    <#
    .SYNOPSIS
        Splits the generated tasks across the three severity files, each guarded by an assert for
        every role-scoped list its tasks loop over.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Task,

        [string] $StigName
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
        $roleVariables = [System.Collections.Generic.SortedSet[string]]::new()
    }
    process {
        $null = $items.Add(@{
            Id = $Task.Rule.Id
            Severity = $Task.Rule.Severity
            Value = $Task.Task
        })

        foreach ($name in @($Task.RoleVariable)) {
            if ($name) { $null = $roleVariables.Add($name) }
        }
    }
    end {
        $bySeverity = Group-AnsibleRuleBySeverity -InputObject $items.ToArray()

        $asserts = @(foreach ($name in $roleVariables) {
            ConvertTo-Yaml (New-AnsibleRoleVariableAssert -TaskName $name -StigName $StigName) -KeepArray
        })

        [ordered] @{
            cat1 = Add-AnsibleRoleVariableAssert -Task ($bySeverity.high.Values) -Assert $asserts
            cat2 = Add-AnsibleRoleVariableAssert -Task ($bySeverity.medium.Values) -Assert $asserts
            cat3 = Add-AnsibleRoleVariableAssert -Task ($bySeverity.low.Values) -Assert $asserts
        }
    }
}

<#
.SYNOPSIS
    One severity file's yaml - the asserts first, then its tasks.
.DESCRIPTION
    Repeated in every non-empty severity file rather than written once somewhere central, because
    tasks/main.yml imports each of the three behind its own tag: a run of --tags cat2 alone has to
    assert too. An empty file gets nothing, since Save-AnsibleRoleFile would then write a file
    holding only a guard for tasks that are not there.
#>
function Add-AnsibleRoleVariableAssert {
    param ($Task, [string[]] $Assert)

    $tasks = @($Task | ForEach-Object { ConvertTo-Yaml $_ -KeepArray })
    if ($tasks.Count -eq 0) { return $tasks }

    @($Assert) + $tasks
}

<#
.SYNOPSIS
    The assert guarding one role-scoped list.
.DESCRIPTION
    An empty list is not an error in ansible, it is a no-op, so a site role whose website list is
    still [] hardens nothing and says nothing. ADR-0001 says a conversion that cannot be honest
    fails loudly; this is that failure wearing a no-op's clothes. See #57.
#>
function New-AnsibleRoleVariableAssert {
    param ([string] $TaskName, [string] $StigName)

    $variable = Get-AnsibleRoleVariableName -TaskName $TaskName -StigName $StigName

    [ordered] @{
        'name' = 'Assert {0} names something' -f $variable
        'ansible.builtin.assert' = [ordered] @{
            'that' = @('{0} | length > 0' -f $variable)
            'fail_msg' = '{0} is empty, so this role would configure nothing. Set it in defaults/main/main.yml or group_vars.' -f $variable
        }
    }
}
