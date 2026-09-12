#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-RegistryRule {
        param (
            $Id = 'V-170',
            $ValueData = '1',
            $ValueType = 'DWORD',
            $OrganizationValueRequired = $false
        )

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            Key = 'HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\System'
            ValueName = 'EnableSmartScreen'
            ValueType = $ValueType
            ValueData = $ValueData
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function Get-RegistryTask {
        param ($Rule, $OrganizationalSetting = @{})

        (Invoke-Generator -Generator 'Build-AnsibleRegistryTask' -Rule $Rule `
            -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $OrganizationalSetting).Task
    }
}

Describe 'Build-AnsibleRegistryTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleRegistryTask' `
        -Module 'ansible.windows.win_regedit' `
        -Factory { New-RegistryRule }

    Context 'the task it builds' {

        It 'points win_regedit at the key and value the rule names' {
            $regedit = (Get-RegistryTask -Rule (New-RegistryRule)).'ansible.windows.win_regedit'

            $regedit.path | Should-Be 'HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\System'
            $regedit.name | Should-Be 'EnableSmartScreen'
        }

        # win_regedit wants the type lowercased; the STIG spells it DWORD.
        It 'lowercases the value type' {
            $regedit = (Get-RegistryTask -Rule (New-RegistryRule)).'ansible.windows.win_regedit'

            $regedit.type | Should-Be 'dword'
        }

        It 'passes a numeric value through as a number' {
            $regedit = (Get-RegistryTask -Rule (New-RegistryRule)).'ansible.windows.win_regedit'

            $regedit.data | Should-Be 1
            $regedit.data -is [int] | Should-BeTrue
        }

        It 'leaves a value that is not a number as text' {
            $regedit = (Get-RegistryTask -Rule (New-RegistryRule -ValueData 'ProductName' -ValueType 'String')).'ansible.windows.win_regedit'

            $regedit.data | Should-Be 'ProductName'
        }
    }

    # Sub-rules collapse into one block under one toggle, so an operator switches the whole
    # requirement off rather than half of it.
    Context 'sub-rules that share a base id' {

        BeforeAll {
            $script:grouped = InModuleScope -ModuleName PowerStigConverter {
                @(
                    [pscustomobject] @{
                        Id = 'V-171.a'; Severity = 'medium'; DuplicateOf = ''
                        Key = 'HKLM\Software\Policies\Alpha'; ValueName = 'One'
                        ValueType = 'DWORD'; ValueData = '1'; OrganizationValueRequired = $false
                    }
                    [pscustomobject] @{
                        Id = 'V-171.b'; Severity = 'medium'; DuplicateOf = ''
                        Key = 'HKLM\Software\Policies\Alpha'; ValueName = 'Two'
                        ValueType = 'DWORD'; ValueData = '2'; OrganizationValueRequired = $false
                    }
                ) | ConvertTo-AnsibleTask -RuleType 'Registry' -StigName 'WindowsServer-2022-MS'
            }
        }

        It 'nests both sub-rules in one block' {
            @($grouped).Count | Should-Be 1
            @($grouped.Task.block).Count | Should-Be 2
        }

        It 'guards the block with one toggle named for the base id' {
            $grouped.Task.when | Should-Be 'stig_server_2022_171_when'
        }
    }

    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a value' {
            $rule = New-RegistryRule -ValueData '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-170" ValueData="1" />'

            $regedit = (Get-RegistryTask -Rule $rule -OrganizationalSetting $orgSetting).'ansible.windows.win_regedit'

            $regedit.data | Should-Be '{{ stig_server_2022_170_enablesmartscreen }}'
        }

        It 'guards an unanswered value with an assert' {
            $rule = New-RegistryRule -ValueData '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-170" ValueData="" />'

            $task = Get-RegistryTask -Rule $rule -OrganizationalSetting $orgSetting

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }
}
