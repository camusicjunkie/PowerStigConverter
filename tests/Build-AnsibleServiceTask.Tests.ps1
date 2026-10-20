#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-ServiceRule {
        param ($Id = 'V-160', $OrganizationValueRequired = $false, $ServiceState = 'Running', $StartupType = 'Automatic')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            ServiceName = 'WinDefend'
            StartupType = $StartupType
            ServiceState = $ServiceState
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function Get-ServiceTask {
        param ($Rule, $OrganizationalSetting = @{})

        (Invoke-Generator -Generator 'Build-AnsibleServiceTask' -Rule $Rule `
            -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $OrganizationalSetting).Task
    }

    # The member of the block that carries the module.
    function Get-BlockMember {
        param ($Task, $Module)

        @($Task.block | Where-Object { $_.Contains($Module) })[0]
    }
}

# The service task is a block: gather the service, then set it - asserting first that it is
# installed when the rule wants it running. See docs/adr/0022.
Describe 'Build-AnsibleServiceTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleServiceTask' `
        -Module 'ansible.windows.win_service' `
        -Factory { New-ServiceRule }

    Context 'the task it builds' {

        It 'gathers the service the rule names' {
            $gather = Get-BlockMember -Task (Get-ServiceTask -Rule (New-ServiceRule)) -Module 'ansible.windows.win_service_info'

            $gather.'ansible.windows.win_service_info'.name | Should-Be 'WinDefend'
        }

        It 'sets the service the rule names' {
            $set = Get-BlockMember -Task (Get-ServiceTask -Rule (New-ServiceRule)) -Module 'ansible.windows.win_service'

            $set.'ansible.windows.win_service'.name | Should-Be 'WinDefend'
        }

        # Named for the rule, because the service name may be a variable reference by now.
        It 'names the register for the rule, not the service' {
            $register = (Get-ServiceTask -Rule (New-ServiceRule)).block[0].register

            $register | Should-Be (Get-ExpectedRegisterName -TaskId 'V-160' `
                    -StigName 'WindowsServer-2022-MS' -Suffix 'service_info')
        }

        It 'names the task for what it sets' {
            $task = Get-ServiceTask -Rule (New-ServiceRule)

            $task.name | Should-Be 'V-160 | MEDIUM | Set WinDefend service to Automatic and started'
        }
    }

    # PowerStig writes the DSC Service resource's startup types; win_service spells them its own way.
    Context 'StartupType' {

        It 'sets start_mode <Expected> for <StartupType>' -ForEach @(
            @{ StartupType = 'Automatic'; Expected = 'auto' }
            @{ StartupType = 'Manual'; Expected = 'manual' }
            @{ StartupType = 'Disabled'; Expected = 'disabled' }
        ) {
            $set = Get-BlockMember -Task (Get-ServiceTask -Rule (New-ServiceRule -StartupType $StartupType)) -Module 'ansible.windows.win_service'

            $set.'ansible.windows.win_service'.start_mode | Should-Be $Expected
        }

        It 'throws rather than guessing a start mode for an unrecognized StartupType' {
            { Get-ServiceTask -Rule (New-ServiceRule -StartupType 'Boot') } | Should-Throw
        }
    }

    # ServiceState is the STIG's own fixed answer (never an organization value). See #100.
    Context 'ServiceState' {

        It 'sets state <Expected> when the rule wants the service <ServiceState>' -ForEach @(
            @{ ServiceState = 'Running'; Expected = 'started' }
            @{ ServiceState = 'Stopped'; Expected = 'stopped' }
        ) {
            $set = Get-BlockMember -Task (Get-ServiceTask -Rule (New-ServiceRule -ServiceState $ServiceState)) -Module 'ansible.windows.win_service'

            $set.'ansible.windows.win_service'.state | Should-Be $Expected
        }

        # Missing/unrecognized ServiceState must not silently fall back to 'started' - that is
        # the exact wrong-direction failure #100 fixed. See docs/research/0100-servicerule-state-survey.md.
        It 'throws rather than guessing a direction when ServiceState is missing' {
            { Get-ServiceTask -Rule (New-ServiceRule -ServiceState $null) } | Should-Throw
        }

        It 'throws rather than guessing a direction for an unrecognized ServiceState' {
            { Get-ServiceTask -Rule (New-ServiceRule -ServiceState 'Paused') } | Should-Throw
        }
    }

    # win_service fails on a name the target does not have. Whether that is a finding depends on
    # which way the rule points. See #170 and docs/adr/0022.
    Context 'a service the target does not have' {

        It 'fails a rule that wants it running, before setting it' {
            $task = Get-ServiceTask -Rule (New-ServiceRule -ServiceState 'Running')
            $register = $task.block[0].register

            $task.block[1].'ansible.builtin.assert'.that | Should-Be "$register.services | length == 1"
            $task.block[2].Contains('ansible.windows.win_service') | Should-BeTrue
            $task.block[2].Contains('when') | Should-BeFalse
        }

        It 'skips setting it for a rule that wants it stopped, which it already is' {
            $task = Get-ServiceTask -Rule (New-ServiceRule -ServiceState 'Stopped' -StartupType 'Disabled')
            $register = $task.block[0].register

            @($task.block | Where-Object { $_.Contains('ansible.builtin.assert') }).Count | Should-Be 0
            $task.block[1].Contains('ansible.windows.win_service') | Should-BeTrue
            $task.block[1].when | Should-Be "$register.services | length == 1"
        }
    }

    # Service is one of two rule types whose task needs more than one field, so both the name and
    # the startup type are organization values and each gets its own variable.
    Context 'a value the organization decides' {

        BeforeAll {
            $script:answered = '<OrganizationalSetting id="V-160" ServiceName="WinDefend" StartupType="Automatic" />'
        }

        It 'interpolates a variable for the service name' {
            $task = Get-ServiceTask -Rule (New-ServiceRule -OrganizationValueRequired $true) `
                -OrganizationalSetting (New-ContractOrgSetting $answered)

            (Get-BlockMember -Task $task -Module 'ansible.windows.win_service_info').'ansible.windows.win_service_info'.name |
                Should-Be '{{ stig_server_2022_160_servicename }}'
            (Get-BlockMember -Task $task -Module 'ansible.windows.win_service').'ansible.windows.win_service'.name |
                Should-Be '{{ stig_server_2022_160_servicename }}'
        }

        # The variable holds PowerStig's word, so the mapping happens when the play runs, and an
        # Ansible word given with -e passes through.
        It 'maps the startup type variable to a start mode when the play runs' {
            $task = Get-ServiceTask -Rule (New-ServiceRule -OrganizationValueRequired $true) `
                -OrganizationalSetting (New-ContractOrgSetting $answered)

            (Get-BlockMember -Task $task -Module 'ansible.windows.win_service').'ansible.windows.win_service'.start_mode |
                Should-Be "{{ {'Automatic': 'auto', 'Disabled': 'disabled', 'Manual': 'manual'}.get(stig_server_2022_160_startuptype, stig_server_2022_160_startuptype) }}"
            $task.name | Should-BeLikeString '*{{ stig_server_2022_160_startuptype }}*'
        }

        It 'guards an unanswered field with an assert naming that field' {
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-160" ServiceName="WinDefend" StartupType="" />'

            $task = Get-ServiceTask -Rule (New-ServiceRule -OrganizationValueRequired $true) -OrganizationalSetting $orgSetting

            $task.block[0].'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_server_2022_160_startuptype | default("", true) | length > 0')
        }
    }
}
