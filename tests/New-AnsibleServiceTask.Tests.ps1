#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-ServiceRule {
        param ($Id = 'V-160', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            ServiceName = 'WinDefend'
            StartupType = 'Automatic'
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function Get-ServiceTask {
        param ($Rule, $OrganizationalSetting = @{})

        (Invoke-Generator -Generator 'New-AnsibleServiceTask' -Rule $Rule `
            -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $OrganizationalSetting).Task
    }
}

# The service task is a block: gather the service state, then assert on it. There is no ansible
# module that sets a startup type and asserts in one step.
Describe 'New-AnsibleServiceTask' {

    Add-GeneratorContractTests -Generator 'New-AnsibleServiceTask' `
        -Module 'ansible.windows.win_service_info' `
        -Factory { New-ServiceRule }

    Context 'the task it builds' {

        It 'gathers the service the rule names' {
            $gather = (Get-ServiceTask -Rule (New-ServiceRule)).block[0]

            $gather.'ansible.windows.win_service_info'.name | Should-Be 'WinDefend'
        }

        It 'asserts on what it registered' {
            $task = Get-ServiceTask -Rule (New-ServiceRule)

            $register = $task.block[0].register
            $task.block[1].'ansible.builtin.assert'.that | Should-BeLikeString "$register*"
        }

        # Named for the rule, because the service name may be a variable reference by now.
        It 'names the register for the rule, not the service' {
            $register = (Get-ServiceTask -Rule (New-ServiceRule)).block[0].register

            $register | Should-Be 'stig_server_2022_160_service_info'
        }

        It 'names the task for the rule id, its severity and the service' {
            $task = Get-ServiceTask -Rule (New-ServiceRule)

            $task.name | Should-Be 'V-160 | MEDIUM | Assert WinDefend service is set to Automatic'
        }
    }

    # Service is one of two rule types whose task needs more than one field, so both the name and
    # the startup type are organization values and each gets its own variable.
    Context 'a value the organization decides' {

        It 'interpolates a variable for the service name and another for the startup type' {
            $rule = New-ServiceRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-160" ServiceName="WinDefend" StartupType="Automatic" />'

            $task = Get-ServiceTask -Rule $rule -OrganizationalSetting $orgSetting

            $task.block[0].'ansible.windows.win_service_info'.name |
                Should-Be '{{ stig_server_2022_160_servicename }}'
            $task.name | Should-BeLikeString '*{{ stig_server_2022_160_startuptype }}*'
        }

        It 'guards an unanswered field with an assert naming that field' {
            $rule = New-ServiceRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-160" ServiceName="WinDefend" StartupType="" />'

            $task = Get-ServiceTask -Rule $rule -OrganizationalSetting $orgSetting

            $task.block[0].'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_server_2022_160_startuptype | default("", true) | length > 0')
        }
    }
}
