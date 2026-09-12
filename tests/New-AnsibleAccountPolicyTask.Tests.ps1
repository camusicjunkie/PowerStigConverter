#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

# At file scope, not only in BeforeAll: Pester builds the test tree at discovery, so
# Add-GeneratorContractTests has to exist before Describe runs.
. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    # Again at run time, because It bodies execute in a scope that only sees what BeforeAll set
    # up - this is where the contract's helpers have to be.
    . $PSScriptRoot/GeneratorContract.ps1

    function New-AccountPolicyRule {
        param ($Id = 'V-100', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            # Has to be a key of AccountPolicyData.psd1 once punctuation is flattened - the
            # generator looks the ansible section and key up there rather than taking them off
            # the rule.
            PolicyName = 'Maximum password age'
            PolicyValue = '60'
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }
}

Describe 'New-AnsibleAccountPolicyTask' {

    Add-GeneratorContractTests -Generator 'New-AnsibleAccountPolicyTask' `
        -Module 'community.windows.win_security_policy' `
        -Factory { New-AccountPolicyRule }

    Context 'the task it builds' {

        It 'looks the section and key up rather than taking them off the rule' {
            $task = (Invoke-Generator -Generator 'New-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $policy = $task.'community.windows.win_security_policy'
            $policy.section | Should-Be 'System Access'
            $policy.key | Should-Be 'MaximumPasswordAge'
        }

        # win_security_policy wants the number, and yaml would otherwise read a quoted 60 as text.
        It 'passes a numeric value through as a number' {
            $task = (Invoke-Generator -Generator 'New-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $task.'community.windows.win_security_policy'.value | Should-Be 60
            $task.'community.windows.win_security_policy'.value -is [int] | Should-BeTrue
        }

        It 'names the task for the rule id, its severity and the policy' {
            $task = (Invoke-Generator -Generator 'New-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-100 | MEDIUM | Maximum password age'
        }
    }

    # Item 7 of the contract. The value DISA leaves to the adopting organization never reaches the
    # task as a literal - it is declared in defaults/ and interpolated. See docs/adr/0003.
    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a value' {
            $rule = New-AccountPolicyRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />'

            $task = (Invoke-Generator -Generator 'New-AnsibleAccountPolicyTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task

            $task.'community.windows.win_security_policy'.value |
                Should-Be '{{ stig_server_2022_100_maximum_password_age }}'
        }

        # Normally the conversion refuses outright; this is what -AllowIncompleteOrganizationValue
        # produces instead, so an unanswered value fails the play rather than setting nothing.
        It 'guards an unanswered value with an assert' {
            $rule = New-AccountPolicyRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />'

            $task = (Invoke-Generator -Generator 'New-AnsibleAccountPolicyTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }
}
