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

        $common = @{ Assert = $asserts; StigName = $StigName }

        [ordered] @{
            cat1 = Format-AnsibleSeverityFile -Task ($bySeverity.high.Values) -Severity 'high' @common
            cat2 = Format-AnsibleSeverityFile -Task ($bySeverity.medium.Values) -Severity 'medium' @common
            cat3 = Format-AnsibleSeverityFile -Task ($bySeverity.low.Values) -Severity 'low' @common
        }
    }
}

<#
.SYNOPSIS
    One severity file's yaml - the asserts first, then its tasks.
.DESCRIPTION
    The asserts are repeated in every severity file that has tasks rather than written once
    somewhere central, because tasks/main.yml imports each of the three behind its own tag: a run
    of --tags cat2 alone has to assert too. A severity with no tasks gets none of them - a guard
    would assert a list nothing in the file reads.

    A severity the STIG carries no rules at still gets a file, holding an empty task list and the
    reason it is empty. tasks/main.yml imports all three statically, and ansible resolves an
    import_tasks when the play is parsed, before any when: is evaluated - so a missing file fails
    the whole role rather than skipping the category. See #118.
#>
function Format-AnsibleSeverityFile {
    param ($Task, [string[]] $Assert, [string] $Severity, [string] $StigName)

    $tasks = @($Task | ForEach-Object { ConvertTo-Yaml $_ -KeepArray })

    if ($tasks.Count -eq 0) {
        # A valid, empty task list rather than an empty file, for the same reason
        # Export-AnsibleHandler writes one: yaml reads this as no tasks, where nothing at all is a
        # parse the import cannot be relied on to survive.
        return @(('# {0} has no {1} severity rules.' -f $StigName, $Severity), '[]')
    }

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
