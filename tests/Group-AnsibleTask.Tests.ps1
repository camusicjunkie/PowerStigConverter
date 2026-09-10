#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Group-AnsibleTask' {

    BeforeAll {
        # The task generators hand this function items shaped @{ GroupId; Output; Task }.
        # A grouped item carries the child task to nest plus the block task it belongs in;
        # PowerStig splits one rule into sub-rules (V-254343.a, .b) that have to become a
        # single ansible block so the whole rule is toggled by one variable.
        function New-GroupedItem {
            param ($GroupId, $ChildName, $BlockName)

            @{
                GroupId = $GroupId
                Task = [ordered] @{ name = $ChildName }
                Output = @{
                    Rule = @{ Id = $GroupId }
                    Task = [ordered] @{
                        name = $BlockName
                        block = [System.Collections.ArrayList]::new()
                    }
                }
            }
        }
    }

    Context 'a rule that was never split' {

        It 'emits an ungrouped item unchanged' {
            $result = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleTask -InputObject @(
                    @{ Output = @{ Rule = @{ Id = 'V-1' }; Task = [ordered] @{ name = 'standalone' } } }
                )
            }

            $result.Task.name | Should-Be 'standalone'
            $result.Task.Keys | Should-NotContainCollection @('block')
        }
    }

    Context 'sub-rules that share a base id' {

        It 'nests every task for an id inside one block' {
            $result = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Builder = ${function:New-GroupedItem} } {
                param ($Builder)
                Group-AnsibleTask -InputObject @(
                    (& $Builder -GroupId 'V-1' -ChildName 'first' -BlockName 'the block')
                    (& $Builder -GroupId 'V-1' -ChildName 'second' -BlockName 'the block')
                )
            }

            @($result).Count | Should-Be 1
            $result.Task.block.name | Should-BeCollection @('first', 'second')
        }

        It 'keeps the block from the first item seen, so one rule yields one toggle' {
            $result = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Builder = ${function:New-GroupedItem} } {
                param ($Builder)
                Group-AnsibleTask -InputObject @(
                    (& $Builder -GroupId 'V-1' -ChildName 'first' -BlockName 'winning block name')
                    (& $Builder -GroupId 'V-1' -ChildName 'second' -BlockName 'losing block name')
                )
            }

            $result.Task.name | Should-Be 'winning block name'
        }

        It 'collects a group whose items do not arrive together' {
            $result = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Builder = ${function:New-GroupedItem} } {
                param ($Builder)
                Group-AnsibleTask -InputObject @(
                    (& $Builder -GroupId 'V-1' -ChildName 'a1' -BlockName 'block one')
                    (& $Builder -GroupId 'V-2' -ChildName 'b1' -BlockName 'block two')
                    (& $Builder -GroupId 'V-1' -ChildName 'a2' -BlockName 'block one')
                )
            }

            @($result).Count | Should-Be 2
            $result[0].Task.block.name | Should-BeCollection @('a1', 'a2')
            $result[1].Task.block.name | Should-BeCollection @('b1')
        }

        It 'emits groups in the order their ids were first seen' {
            $result = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Builder = ${function:New-GroupedItem} } {
                param ($Builder)
                Group-AnsibleTask -InputObject @(
                    (& $Builder -GroupId 'V-300' -ChildName 'c' -BlockName 'third seen')
                    (& $Builder -GroupId 'V-100' -ChildName 'a' -BlockName 'first seen')
                )
            }

            $result.Task.name | Should-BeCollection @('third seen', 'first seen')
        }
    }

    Context 'a mix of split and unsplit rules' {

        It 'emits both the standalone tasks and the blocks' {
            $result = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Builder = ${function:New-GroupedItem} } {
                param ($Builder)
                Group-AnsibleTask -InputObject @(
                    @{ Output = @{ Rule = @{ Id = 'V-9' }; Task = [ordered] @{ name = 'standalone' } } }
                    (& $Builder -GroupId 'V-1' -ChildName 'a1' -BlockName 'the block')
                )
            }

            @($result).Count | Should-Be 2
            $result.Task.name | Should-ContainCollection @('standalone')
            $result.Task.name | Should-ContainCollection @('the block')
        }
    }

    Context 'no tasks at all' {

        It 'accepts an empty collection without emitting anything' {
            $result = InModuleScope -ModuleName PowerStigConverter {
                Group-AnsibleTask -InputObject @()
            }

            @($result).Count | Should-Be 0
        }
    }
}
