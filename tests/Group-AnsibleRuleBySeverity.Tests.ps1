#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Group-AnsibleRuleBySeverity' {

    # Partitions @{ Id; Severity; Value } items into the three DISA categories the role
    # splits its files by: high -> cat1, medium -> cat2, low -> cat3.
    Context 'partitioning by severity' {

        It 'puts each item in the bucket for its severity' {
            $grouped = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleRuleBySeverity -InputObject @(
                    @{ Id = 'V-1'; Severity = 'high'; Value = 'one' }
                    @{ Id = 'V-2'; Severity = 'medium'; Value = 'two' }
                    @{ Id = 'V-3'; Severity = 'low'; Value = 'three' }
                )
            }

            $grouped.high['V-1'] | Should-Be 'one'
            $grouped.medium['V-2'] | Should-Be 'two'
            $grouped.low['V-3'] | Should-Be 'three'
        }

        It 'always returns all three buckets, so the caller can write every cat file' {
            $grouped = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleRuleBySeverity -InputObject @(@{ Id = 'V-1'; Severity = 'high'; Value = 'one' })
            }

            $grouped.Keys | Should-BeCollection @('high', 'medium', 'low')
            $grouped.medium.Count | Should-Be 0
            $grouped.low.Count | Should-Be 0
        }
    }

    Context 'rules that appear more than once' {

        It 'keeps the first value seen for an id and discards later duplicates' {
            $grouped = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleRuleBySeverity -InputObject @(
                    @{ Id = 'V-1'; Severity = 'high'; Value = 'first' }
                    @{ Id = 'V-1'; Severity = 'high'; Value = 'second' }
                )
            }

            $grouped.high['V-1'] | Should-Be 'first'
            $grouped.high.Count | Should-Be 1
        }
    }

    Context 'severities outside the DISA categories' {

        It 'drops an item whose severity has no cat file to go in' {
            $grouped = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleRuleBySeverity -InputObject @(
                    @{ Id = 'V-1'; Severity = 'high'; Value = 'kept' }
                    @{ Id = 'V-2'; Severity = 'unknown'; Value = 'dropped' }
                    @{ Id = 'V-3'; Severity = ''; Value = 'also dropped' }
                )
            }

            ($grouped.high.Count + $grouped.medium.Count + $grouped.low.Count) | Should-Be 1
            $grouped.high['V-1'] | Should-Be 'kept'
        }
    }

    Context 'ordering within a bucket' {

        It 'orders rules by id rather than by arrival, so generated files are stable' {
            $grouped = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleRuleBySeverity -InputObject @(
                    @{ Id = 'V-300'; Severity = 'high'; Value = 'c' }
                    @{ Id = 'V-100'; Severity = 'high'; Value = 'a' }
                    @{ Id = 'V-200'; Severity = 'high'; Value = 'b' }
                )
            }

            $grouped.high.Keys | Should-BeCollection @('V-100', 'V-200', 'V-300')
        }
    }

    Context 'no rules at all' {

        It 'accepts an empty collection and returns three empty buckets' {
            $grouped = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleRuleBySeverity -InputObject @()
            }

            $grouped.high.Count | Should-Be 0
            $grouped.medium.Count | Should-Be 0
            $grouped.low.Count | Should-Be 0
        }
    }
}
