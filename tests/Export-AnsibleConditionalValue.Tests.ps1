#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-TaskItem {
        param ($Id, $Severity = 'medium')

        @{ Rule = [pscustomobject] @{ Id = $Id; Severity = $Severity }; Task = [ordered] @{ 'name' = $Id } }
    }

    function Export-Toggles {
        param ($Items, $StigName = 'WindowsServer-2022-MS')

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Items = $Items; StigName = $StigName } {
            param ($Items, $StigName)
            $Items | Export-AnsibleConditionalValue -StigName $StigName
        }
    }
}

Describe 'Export-AnsibleConditionalValue' {

    # Derived from the generated tasks rather than from the rule list, so defaults/ cannot declare
    # a toggle guarding a task that was never generated.
    Context 'one toggle per generated task' {

        It 'declares the toggle defaulted on' {
            $files = Export-Toggles -Items @(New-TaskItem -Id 'V-100')

            $files.main_default_cat2 | Should-BeCollection @('stig_server_2022_100_when: true')
        }

        It 'files the toggle under the severity of its rule' {
            $files = Export-Toggles -Items @(
                New-TaskItem -Id 'V-1' -Severity 'high'
                New-TaskItem -Id 'V-2' -Severity 'low'
            )

            $files.main_default_cat1 | Should-BeCollection @('stig_server_2022_1_when: true')
            $files.main_default_cat3 | Should-BeCollection @('stig_server_2022_2_when: true')
        }
    }

    # Sub-rules were already collapsed into one block guarded by the base id, so one requirement
    # yields one toggle rather than one per half.
    Context 'sub-rules that share a base id' {

        It 'declares one toggle named for the base id' {
            $files = Export-Toggles -Items @(
                New-TaskItem -Id 'V-171.a'
                New-TaskItem -Id 'V-171.b'
            )

            $files.main_default_cat2 | Should-BeCollection @('stig_server_2022_171_when: true')
        }
    }

    Context 'no tasks at all' {

        It 'names all three files, so tasks/main.yml can import them' {
            $files = Export-Toggles -Items @()

            $files.Keys | Should-BeCollection @('main_default_cat1', 'main_default_cat2', 'main_default_cat3')
        }
    }
}
