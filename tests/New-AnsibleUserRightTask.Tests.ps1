#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-UserRightRule {
        param ($Id = 'V-150', $Identity = 'Administrators,Guests', $Force = 'False', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            DisplayName = 'Access this computer from the network'
            Constant = 'SeNetworkLogonRight'
            Identity = $Identity
            Force = $Force
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }
}

Describe 'New-AnsibleUserRightTask' {

    Add-GeneratorContractTests -Generator 'New-AnsibleUserRightTask' `
        -Module 'ansible.windows.win_user_right' `
        -Factory { New-UserRightRule }

    Context 'the task it builds' {

        # win_user_right takes the constant, not the display name a human reads.
        It 'names the right by its constant' {
            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' `
                -Rule (New-UserRightRule) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.name | Should-Be 'SeNetworkLogonRight'
        }

        It 'names the task for the rule id, its severity and the right' {
            $task = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' `
                -Rule (New-UserRightRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-150 | MEDIUM | Access this computer from the network'
        }
    }

    # A rule that forces the list replaces whoever holds the right; one that does not adds to them.
    Context 'whether the rule replaces the identity list or adds to it' {

        It 'sets the action to <Expected> when Force is <Force>' -ForEach @(
            @{ Force = 'True'; Expected = 'set' }
            @{ Force = 'False'; Expected = 'add' }
        ) {
            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Force $Force) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.action | Should-Be $Expected
        }
    }

    # Item 6. PowerShell unrolls a one-element array back to a string on the way out of an if,
    # which is how a single identity came to reach win_user_right as a string.
    Context 'a value the task needs as a list' {

        It 'splits an identity list the rule carries itself' {
            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' `
                -Rule (New-UserRightRule) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.users -join '|' | Should-Be 'Administrators|Guests'
        }

        It 'keeps a single identity a list rather than unrolling it to a string' {
            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Identity 'Administrators') -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.users -is [array] | Should-BeTrue
            @($right.users).Count | Should-Be 1
        }

        # PowerStig spells "nobody holds this right" as the string NULL.
        It 'sends an empty list when the rule denies the right to everyone' {
            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Identity 'NULL') -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            @($right.users).Count | Should-Be 0
        }
    }

    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a list' {
            $rule = New-UserRightRule -Identity '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-150" Identity="Administrators" />'

            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task.'ansible.windows.win_user_right'

            $right.users | Should-Be '{{ stig_server_2022_150_access_this_computer_from_the_network }}'
        }

        # Splitting on the host instead would make the shape win_user_right receives depend on a
        # jinja expression no test can see, so the whole variable is interpolated as one.
        It 'hands back one reference rather than a split of the reference' {
            $rule = New-UserRightRule -Identity '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-150" Identity="Administrators,Guests" />'

            $right = (Invoke-Generator -Generator 'New-AnsibleUserRightTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task.'ansible.windows.win_user_right'

            @($right.users).Count | Should-Be 1
        }
    }
}
