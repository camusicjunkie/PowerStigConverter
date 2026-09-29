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
            $OrganizationValueRequired = $false,
            $Ensure
        )

        $rule = [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            Key = 'HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\System'
            ValueName = 'EnableSmartScreen'
            ValueType = $ValueType
            ValueData = $ValueData
            OrganizationValueRequired = $OrganizationValueRequired
        }

        # Only when asked for, so the default rule carries no Ensure at all and the cases below
        # can tell 'Present' from 'the field is not there'.
        if ($PSBoundParameters.ContainsKey('Ensure')) {
            $rule | Add-Member -NotePropertyName 'Ensure' -NotePropertyValue $Ensure
        }

        $rule
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

    # ADR-0014: Ensure picks the module's state key, and nothing else in the rule gets a say.
    Context 'a value the STIG says must not be present' {

        It 'removes the value rather than writing one' {
            $rule = New-RegistryRule -Ensure 'Absent' -ValueData '' -ValueType 'None'

            $regedit = (Get-RegistryTask -Rule $rule).'ansible.windows.win_regedit'

            $regedit.state | Should-Be 'absent'
            $regedit.path | Should-Be 'HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\System'
            $regedit.name | Should-Be 'EnableSmartScreen'
        }

        # An empty data/type pair is what win_regedit reads as 'write a REG_NONE value', the exact
        # opposite of what the rule asks for, so the keys have to be gone rather than blank.
        It 'omits data and type entirely' {
            $rule = New-RegistryRule -Ensure 'Absent' -ValueData '' -ValueType 'None'

            $regedit = (Get-RegistryTask -Rule $rule).'ansible.windows.win_regedit'

            @($regedit.Keys) | Should-BeCollection @('path', 'name', 'state')
        }

        # 'Set DisableAntiSpyware' on a task that deletes it reads as the opposite of what it does.
        It 'names the task for the removal' {
            $rule = New-RegistryRule -Ensure 'Absent' -ValueData '' -ValueType 'None'

            (Get-RegistryTask -Rule $rule).name | Should-Be 'V-170 | MEDIUM | Remove EnableSmartScreen'
        }

        # Ensure changes the state key and nothing else: the toggle and the severity file a rule
        # lands in are not its business.
        It 'still guards the task with the toggle for the rule' {
            $rule = New-RegistryRule -Ensure 'Absent' -ValueData '' -ValueType 'None'

            (Get-RegistryTask -Rule $rule).when | Should-Be 'stig_server_2022_170_when'
        }

        # ValueType None is Defender's spelling of 'nothing to type'; Chrome leaves ValueType
        # empty for the same intent. Neither may be read as the removal signal.
        It 'writes the value when only the value type spells nothing' {
            $rule = New-RegistryRule -Ensure 'Present' -ValueData '0' -ValueType 'None'

            $regedit = (Get-RegistryTask -Rule $rule).'ansible.windows.win_regedit'

            $regedit.state | Should-BeNull
            $regedit.data | Should-Be 0
            $regedit.type | Should-Be 'none'
        }

        It 'writes the value when the rule carries no Ensure at all' {
            $regedit = (Get-RegistryTask -Rule (New-RegistryRule)).'ansible.windows.win_regedit'

            $regedit.state | Should-BeNull
            $regedit.data | Should-Be 1
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

        # Registry keys are always backslash-delimited, whatever platform does the converting
        # (see #45), so the block name has to come from that literal character rather than a
        # filesystem cmdlet's separator, which varies by platform.
        It 'names the block for the key leaf regardless of platform separator conventions' {
            $grouped.Task.name | Should-Be 'V-171 | MEDIUM | Alpha'
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
