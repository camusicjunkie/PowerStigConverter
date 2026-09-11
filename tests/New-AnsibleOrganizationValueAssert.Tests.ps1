#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-Assert {
        param ($Rule, $RuleType, $OrgSetting = @{}, $StigName = 'WindowsServer-2022-MS')

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rule = $Rule; RuleType = $RuleType; OrgSetting = $OrgSetting; StigName = $StigName
        } {
            param ($Rule, $RuleType, $OrgSetting, $StigName)
            New-AnsibleOrganizationValueAssert -Rule $Rule -RuleType $RuleType -OrgSetting $OrgSetting -StigName $StigName
        }
    }

    function New-OrgSetting {
        param ([string] $Xml)

        [xml] $document = "<OrganizationalSettings>$Xml</OrganizationalSettings>"

        $settings = @{}
        foreach ($node in $document.OrganizationalSettings.OrganizationalSetting) {
            $settings[$node.id] = $node
        }
        $settings
    }
}

Describe 'New-AnsibleOrganizationValueAssert' {

    # The conversion normally refuses outright, so these only appear in a role generated with
    # -AllowIncompleteOrganizationValue. They are what stops that role setting an empty value.
    Context 'a setting nobody has answered' {

        BeforeAll {
            $script:rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                OrganizationValueRequired = $true
            }
            $script:assert = New-Assert -Rule $rule -RuleType AccountPolicy `
                -OrgSetting (New-OrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />')
        }

        It 'builds an assert task' {
            $assert.Keys | Should-ContainCollection @('ansible.builtin.assert')
        }

        It 'checks the same variable the task interpolates and defaults/ declares' {
            $assert.'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_server_2022_100_account_lockout_duration | default("", true) | length > 0')
        }

        It 'names the rule and the variable in the failure message' {
            $assert.'ansible.builtin.assert'.fail_msg | Should-BeLikeString '*V-100*'
            $assert.'ansible.builtin.assert'.fail_msg | Should-BeLikeString '*stig_server_2022_100_account_lockout_duration*'
        }
    }

    # A type whose task needs several fields gets one check per field, so the failure names the
    # field that is missing rather than the rule as a whole.
    Context 'a multi-field type with one field answered' {

        It 'checks only the field that is blank' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }

            $assert = New-Assert -Rule $rule -RuleType Service `
                -OrgSetting (New-OrgSetting '<OrganizationalSetting id="V-248" ServiceName="WinDefend" StartupType="" />')

            $assert.'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_server_2022_248_startuptype | default("", true) | length > 0')
        }
    }

    # A rule the org settings file has no entry for needs all of its fields, since none of them
    # are there to be read.
    Context 'a rule with no entry at all' {

        It 'checks every field the rule type requires' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }

            $assert = New-Assert -Rule $rule -RuleType Service -OrgSetting @{}

            @($assert.'ansible.builtin.assert'.that).Count | Should-Be 2
        }
    }

    # Only settings unanswered at generation time get one, so the asserts in a role are the list
    # of questions nobody answered and they go away when it is regenerated.
    Context 'a setting that has been answered' {

        It 'builds nothing' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                OrganizationValueRequired = $true
            }

            New-Assert -Rule $rule -RuleType AccountPolicy `
                -OrgSetting (New-OrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />') |
                Should-BeNull
        }

        It 'builds nothing for a rule that carries its own value' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                OrganizationValueRequired = $false
            }

            New-Assert -Rule $rule -RuleType AccountPolicy -OrgSetting @{} | Should-BeNull
        }
    }
}
