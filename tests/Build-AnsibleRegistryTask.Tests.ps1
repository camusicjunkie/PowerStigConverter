#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-RegistryRule {
        param (
            $Id = 'V-170',
            $Key = 'HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows\System',
            $ValueData = '1',
            $ValueType = 'DWORD',
            $OrganizationValueRequired = $false,
            $Ensure
        )

        $rule = [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            Key = $Key
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

            $regedit.path | Should-Be 'HKLM:\Software\Policies\Microsoft\Windows\System'
            $regedit.name | Should-Be 'EnableSmartScreen'
        }

        # win_regedit takes only PowerShell drive paths; PowerStig writes the hive four ways.
        It 'writes <Key> as the drive path win_regedit takes' -ForEach @(
            @{ Key = 'HKEY_LOCAL_MACHINE\Software\Policies'; Path = 'HKLM:\Software\Policies' }
            @{ Key = 'HKEY_LOCAL_Machine\SOFTWARE\Policies'; Path = 'HKLM:\SOFTWARE\Policies' }
            @{ Key = 'HKLM\System\CurrentControlSet'; Path = 'HKLM:\System\CurrentControlSet' }
            @{ Key = 'HKEY_CURRENT_USER\Software\Policies'; Path = 'HKCU:\Software\Policies' }
        ) {
            $regedit = (Get-RegistryTask -Rule (New-RegistryRule -Key $Key)).'ansible.windows.win_regedit'

            $regedit.path | Should-Be $Path
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
            $regedit.path | Should-Be 'HKLM:\Software\Policies\Microsoft\Windows\System'
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

    # ADR-0015: the block is named from the strongest candidate the halves agree on - the key
    # leaf first, the ValueName second, the union of leaves only where they agree on neither.
    # The leaf-sharing case above is 117 of upstream's 133 registry sub-rule groups; these are
    # the other 16.
    Context 'sub-rules that do not share a key leaf' {

        BeforeAll {
            function New-GroupedRegistryTask {
                param ($Half)

                InModuleScope -ModuleName PowerStigConverter -Parameters @{ Half = $Half } {
                    param ($Half)

                    @(foreach ($h in $Half) {
                        [pscustomobject] @{
                            Id = $h.Id; Severity = 'medium'; DuplicateOf = ''
                            Key = $h.Key; ValueName = $h.ValueName
                            ValueType = 'DWORD'; ValueData = '1'; OrganizationValueRequired = $false
                        }
                    }) | ConvertTo-AnsibleTask -RuleType 'Registry' -StigName 'WindowsFirewall-All'
                }
            }
        }

        # WindowsFirewall V-241990: the policy key calls the profile PrivateProfile and the live
        # service key calls the same profile StandardProfile. The union read as two profiles.
        It 'names the block for the ValueName the halves share when their leaves are two spellings of one place' {
            $grouped = New-GroupedRegistryTask -Half @(
                @{ Id = 'V-241990.a'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile'; ValueName = 'EnableFirewall' }
                @{ Id = 'V-241990.b'; Key = 'HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile'; ValueName = 'EnableFirewall' }
            )

            $grouped.Task.name | Should-Be 'V-241990 | MEDIUM | EnableFirewall'
        }

        # WindowsClient-10 V-220835 / -11 V-253394: the same shape parent key to child key rather
        # than sibling to sibling, which shipped as 'Config, DeliveryOptimization'.
        It 'names it for the shared ValueName when one leaf is the parent of the other' {
            $grouped = New-GroupedRegistryTask -Half @(
                @{ Id = 'V-220835.a'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; ValueName = 'DODownloadMode' }
                @{ Id = 'V-220835.b'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization\Config'; ValueName = 'DODownloadMode' }
            )

            $grouped.Task.name | Should-Be 'V-220835 | MEDIUM | DODownloadMode'
        }

        # SqlServer-2016 V-213967: several protocol keys, several values, one requirement - here
        # the union is what describes it, and it is the fallback rather than the default.
        It 'falls back to the union of leaves when the halves agree on neither leaf nor ValueName' {
            $grouped = New-GroupedRegistryTask -Half @(
                @{ Id = 'V-213967.a'; Key = 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'; ValueName = 'DisabledByDefault' }
                @{ Id = 'V-213967.e'; Key = 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'; ValueName = 'Enabled' }
            )

            $grouped.Task.name | Should-Be 'V-213967 | MEDIUM | Client, Server'
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
