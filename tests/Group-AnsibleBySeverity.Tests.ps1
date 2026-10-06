#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Group-BySeverity {
        param ($Items)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Items = $Items } {
            param ($Items)
            Group-AnsibleBySeverity -InputObject $Items
        }
    }
}

Describe 'Group-AnsibleBySeverity' {

    # The role splits its files by DISA category: high -> cat1, medium -> cat2, low -> cat3. This
    # is where the generator maps them. See #130.
    Context 'sorting into categories' {

        It 'puts each item in the category for its severity' {
            $grouped = Group-BySeverity -Items @(
                @{ Id = 'V-1'; Severity = 'high'; Value = 'one' }
                @{ Id = 'V-2'; Severity = 'medium'; Value = 'two' }
                @{ Id = 'V-3'; Severity = 'low'; Value = 'three' }
            )

            $grouped.cat1.Item['V-1'] | Should-Be 'one'
            $grouped.cat2.Item['V-2'] | Should-Be 'two'
            $grouped.cat3.Item['V-3'] | Should-Be 'three'
        }

        It 'names the severity each category holds' {
            $grouped = Group-BySeverity -Items @()

            ($grouped.Values.Severity) -join ',' | Should-Be 'high,medium,low'
        }

        It 'always returns all three categories, in order, so the caller can write every file' {
            $grouped = Group-BySeverity -Items @(@{ Id = 'V-1'; Severity = 'high'; Value = 'one' })

            ($grouped.Keys) -join ',' | Should-Be 'cat1,cat2,cat3'
            $grouped.cat2.Item.Count | Should-Be 0
            $grouped.cat3.Item.Count | Should-Be 0
        }
    }

    Context 'an id that appears more than once' {

        It 'keeps the first value' {
            $grouped = Group-BySeverity -Items @(
                @{ Id = 'V-1'; Severity = 'high'; Value = 'first' }
                @{ Id = 'V-1'; Severity = 'high'; Value = 'second' }
            )

            $grouped.cat1.Item['V-1'] | Should-Be 'first'
            $grouped.cat1.Item.Count | Should-Be 1
        }
    }

    Context 'severities outside the DISA categories' {

        It 'drops an item whose severity has no file to go in' {
            $grouped = Group-BySeverity -Items @(
                @{ Id = 'V-1'; Severity = 'high'; Value = 'kept' }
                @{ Id = 'V-2'; Severity = 'unknown'; Value = 'dropped' }
                @{ Id = 'V-3'; Severity = ''; Value = 'also dropped' }
            )

            ($grouped.Values | ForEach-Object { $_.Item.Count } | Measure-Object -Sum).Sum | Should-Be 1
            $grouped.cat1.Item['V-1'] | Should-Be 'kept'
        }
    }

    Context 'ordering within a category' {

        It 'orders items by id rather than by arrival, so generated files are stable' {
            $grouped = Group-BySeverity -Items @(
                @{ Id = 'V-300'; Severity = 'high'; Value = 'c' }
                @{ Id = 'V-100'; Severity = 'high'; Value = 'a' }
                @{ Id = 'V-200'; Severity = 'high'; Value = 'b' }
            )

            ($grouped.cat1.Item.Keys) -join ',' | Should-Be 'V-100,V-200,V-300'
        }
    }
}
