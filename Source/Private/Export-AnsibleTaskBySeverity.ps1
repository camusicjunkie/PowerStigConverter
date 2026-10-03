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
        # Keyed by name: a role-scoped list read by many rules is asserted once, and in name order.
        $roleVariables = [System.Collections.SortedList]::new()
    }
    process {
        $null = $items.Add(@{
            Id = $Task.Rule.Id
            Severity = $Task.Rule.Severity
            Value = $Task.Task
        })

        foreach ($variable in @($Task.RoleVariable)) {
            if ($variable.Assert) { $roleVariables[$variable.Name] = $variable.Assert }
        }
    }
    end {
        $asserts = @(foreach ($assert in $roleVariables.Values) { ConvertTo-Yaml $assert -KeepArray })

        $files = [ordered] @{}
        foreach ($category in (Group-AnsibleBySeverity -InputObject $items.ToArray()).GetEnumerator()) {
            $files[$category.Key] = Format-AnsibleSeverityFile -Task $category.Value.Item.Values `
                -Severity $category.Value.Severity -Assert $asserts -StigName $StigName
        }
        $files
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
