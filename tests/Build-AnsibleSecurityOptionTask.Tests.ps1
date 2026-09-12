#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-SecurityOptionRule {
        param ($Id = 'V-140', $OptionValue = '30', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            # Flattens to a key of SecurityOptionData.psd1, where the ansible section and key live.
            OptionName = 'Domain member: Maximum machine account password age'
            OptionValue = $OptionValue
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }
}

Describe 'Build-AnsibleSecurityOptionTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSecurityOptionTask' `
        -Module 'community.windows.win_security_policy' `
        -Factory { New-SecurityOptionRule }

    Context 'the task it builds' {

        It 'looks the section and key up rather than taking them off the rule' {
            $policy = (Invoke-Generator -Generator 'Build-AnsibleSecurityOptionTask' `
                -Rule (New-SecurityOptionRule) -StigName 'WindowsServer-2022-MS').Task.'community.windows.win_security_policy'

            $policy.section | Should-Be 'Registry Values'
            $policy.key | Should-BeLikeString '*MaximumPasswordAge'
        }

        It 'names the task for the rule id, its severity and the option' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleSecurityOptionTask' `
                -Rule (New-SecurityOptionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-140 | MEDIUM | Domain member: Maximum machine account password age'
        }
    }

    # win_security_policy wants the number, not the word. The table is keyed by the value
    # asked for - indexing by property name misses and the cast then yields 0.
    Context 'an option expressed as Enabled or Disabled' {

        It 'maps <OptionValue> to <Expected>' -ForEach @(
            @{ OptionValue = 'Enabled'; Expected = 1 }
            @{ OptionValue = 'Disabled'; Expected = 0 }
        ) {
            $rule = [pscustomobject] @{
                Id = 'V-141'
                Severity = 'medium'
                DuplicateOf = ''
                OptionName = 'Accounts: Guest account status'
                OptionValue = $OptionValue
                OrganizationValueRequired = $false
            }

            $policy = (Invoke-Generator -Generator 'Build-AnsibleSecurityOptionTask' `
                -Rule $rule -StigName 'WindowsServer-2022-MS').Task.'community.windows.win_security_policy'

            $policy.value | Should-Be $Expected
        }
    }

    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a value' {
            $rule = New-SecurityOptionRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-140" OptionValue="30" />'

            $policy = (Invoke-Generator -Generator 'Build-AnsibleSecurityOptionTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task.'community.windows.win_security_policy'

            $policy.value | Should-BeLikeString '{{ stig_server_2022_140_*'
        }

        It 'guards an unanswered value with an assert' {
            $rule = New-SecurityOptionRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-140" OptionValue="" />'

            $task = (Invoke-Generator -Generator 'Build-AnsibleSecurityOptionTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }
}
