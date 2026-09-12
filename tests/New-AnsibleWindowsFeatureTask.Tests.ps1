#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-WindowsFeatureRule {
        param ($Id = 'V-130', $Ensure = 'Absent')

        [pscustomobject] @{
            Id = $Id
            Severity = 'high'
            DuplicateOf = ''
            Name = 'TFTP-Client'
            Ensure = $Ensure
        }
    }
}

Describe 'New-AnsibleWindowsFeatureTask' {

    Add-GeneratorContractTests -Generator 'New-AnsibleWindowsFeatureTask' `
        -Module 'ansible.windows.win_feature' `
        -Factory { New-WindowsFeatureRule }

    Context 'the task it builds' {

        It 'sets the feature named on the rule to the state it asks for' {
            $task = (Invoke-Generator -Generator 'New-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $feature = $task.'ansible.windows.win_feature'
            $feature.name | Should-Be 'TFTP-Client'
            $feature.state | Should-Be 'Absent'
        }

        It 'carries Present through as well as Absent' {
            $task = (Invoke-Generator -Generator 'New-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule -Ensure 'Present') -StigName 'WindowsServer-2022-MS').Task

            $task.'ansible.windows.win_feature'.state | Should-Be 'Present'
        }

        It 'names the task for the rule id, its severity and the change it makes' {
            $task = (Invoke-Generator -Generator 'New-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-130 | HIGH | Set TFTP-Client to Absent'
        }
    }

    # The generator reads $name into its splat one line before assigning it, so the toggle is
    # built from an empty task name. It is invisible today because the Conditional variable type
    # is named from the rule id alone and ignores the task name - but the toggle still has to be
    # the one defaults/ declares, so pin it.
    Context 'the conditional toggle' {

        It 'names the toggle from the rule id, whatever the task name' {
            $task = (Invoke-Generator -Generator 'New-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $task.when | Should-Be 'stig_server_2022_130_when'
        }

        It 'does not carry a toggle from the rule converted before it' {
            $first = New-WindowsFeatureRule -Id 'V-130'
            $second = New-WindowsFeatureRule -Id 'V-131'

            $tasks = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rules = @($first, $second) } {
                param ($Rules)
                $Rules | New-AnsibleWindowsFeatureTask -StigName 'WindowsServer-2022-MS'
            }

            $tasks[1].Task.when | Should-Be 'stig_server_2022_131_when'
        }
    }
}
