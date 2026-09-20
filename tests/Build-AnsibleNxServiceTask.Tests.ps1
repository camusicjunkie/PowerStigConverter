#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-NxServiceRule {
        param ($Id = 'V-230', $Name = 'sshd', $Enabled = 'False', $State = '')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            Name = $Name
            Enabled = $Enabled
            State = $State
        }
    }
}

# Every in-scope product is systemd-era, so this targets systemd_service directly rather than
# the generic service module. See ADR 0008.
Describe 'Build-AnsibleNxServiceTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleNxServiceTask' `
        -Module 'ansible.builtin.systemd_service' `
        -Factory { New-NxServiceRule }

    Context 'the task it builds' {

        It 'names the service and escalates' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleNxServiceTask' `
                -Rule (New-NxServiceRule) -StigName 'OracleLinux-8').Task

            $task.'ansible.builtin.systemd_service'.name | Should-Be 'sshd'
            $task.become | Should-BeTrue
        }

        It 'converts Enabled with an explicit -eq, never a coercion' {
            $enabled = (Invoke-Generator -Generator 'Build-AnsibleNxServiceTask' `
                -Rule (New-NxServiceRule -Enabled 'True') -StigName 'OracleLinux-8').Task.'ansible.builtin.systemd_service'.enabled

            $enabled | Should-BeTrue
            $enabled | Should-HaveType ([bool])
        }

        It 'reads a disabled rule as disabled' {
            $enabled = (Invoke-Generator -Generator 'Build-AnsibleNxServiceTask' `
                -Rule (New-NxServiceRule -Enabled 'False') -StigName 'OracleLinux-8').Task.'ansible.builtin.systemd_service'.enabled

            $enabled | Should-BeFalse
        }

        It 'names the task for the assertion it makes' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleNxServiceTask' `
                -Rule (New-NxServiceRule -Name 'sshd' -Enabled 'False') -StigName 'OracleLinux-8').Task

            $task.name | Should-Be 'V-230 | MEDIUM | Ensure sshd service is disabled'
        }
    }

    # Both in-scope rules carry an empty State, so state: must be omitted rather than defaulted.
    Context 'a rule that does not name a state' {

        It 'leaves state out rather than sending it empty' {
            $systemd = (Invoke-Generator -Generator 'Build-AnsibleNxServiceTask' `
                -Rule (New-NxServiceRule -State '') -StigName 'OracleLinux-8').Task.'ansible.builtin.systemd_service'

            $systemd.Contains('state') | Should-BeFalse
        }

        It 'includes state, and appends it to the detail, when the rule does name one' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleNxServiceTask' `
                -Rule (New-NxServiceRule -Name 'sshd' -Enabled 'True' -State 'Running') -StigName 'OracleLinux-8').Task

            $task.'ansible.builtin.systemd_service'.state | Should-Be 'Running'
            $task.name | Should-Be 'V-230 | MEDIUM | Ensure sshd service is enabled and Running'
        }
    }
}
