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

Describe 'Build-AnsibleWindowsFeatureTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleWindowsFeatureTask' `
        -Module 'ansible.windows.win_feature' `
        -Factory { New-WindowsFeatureRule }

    Context 'the task it builds' {

        It 'sets the feature named on the rule to the state it asks for' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $feature = $task.'ansible.windows.win_feature'
            $feature.name | Should-Be 'TFTP-Client'
            $feature.state | Should-Be 'absent'
        }

        # win_feature documents its state choices lowercase and validates them case-sensitively,
        # so PowerStig's Present/Absent is translated rather than passed through. See ADR 0014
        # and #117.
        It 'spells Present the way the module does, as well as Absent' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule -Ensure 'Present') -StigName 'WindowsServer-2022-MS').Task

            $task.'ansible.windows.win_feature'.state | Should-Be 'present'
        }

        It 'takes the present path for a rule that states no Ensure at all' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule -Ensure '') -StigName 'WindowsServer-2022-MS').Task

            $task.'ansible.windows.win_feature'.state | Should-Be 'present'
        }

        # A feature the target does not ship is already absent; win_feature fails on the name.
        # See #146.
        It 'tolerates only the not-valid-name failure when removing a feature' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $register = Get-ExpectedRegisterName -TaskId 'V-130' -StigName 'WindowsServer-2022-MS' -Suffix 'feature_result'
            $task.register | Should-Be $register
            $task.failed_when | Should-Be "$register is failed and 'is not valid' not in ($register.msg | default(''))"
        }

        It 'leaves installing a feature to fail on any error' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule -Ensure 'Present') -StigName 'WindowsServer-2022-MS').Task

            $task.Contains('failed_when') | Should-BeFalse
            $task.Contains('register') | Should-BeFalse
        }

        It 'names the task for the rule id, its severity and the change it makes' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-130 | HIGH | Set TFTP-Client to absent'
        }
    }

    # The generator reads $name a line before assigning it. Inert, because a Conditional
    # variable is named from the rule id alone - but pin the toggle anyway. See #9.
    Context 'the conditional toggle' {

        It 'names the toggle from the rule id, whatever the task name' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleWindowsFeatureTask' `
                -Rule (New-WindowsFeatureRule) -StigName 'WindowsServer-2022-MS').Task

            $task.when | Should-Be 'stig_server_2022_130_when | bool'
        }

        It 'does not carry a toggle from the rule converted before it' {
            $first = New-WindowsFeatureRule -Id 'V-130'
            $second = New-WindowsFeatureRule -Id 'V-131'

            $tasks = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rules = @($first, $second) } {
                param ($Rules)
                $Rules | ConvertTo-AnsibleTask -RuleType 'WindowsFeature' -StigName 'WindowsServer-2022-MS'
            }

            $tasks[1].Task.when | Should-Be 'stig_server_2022_131_when | bool'
        }
    }
}
