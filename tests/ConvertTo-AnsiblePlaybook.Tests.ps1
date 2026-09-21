#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-RuleGroup {
        param ($PowerStigRule, $Rules)

        [pscustomobject] @{ PowerStigRule = $PowerStigRule; StigRule = $Rules }
    }

    # A single-item result collapses to a scalar crossing the function boundary, so every call
    # site below that needs the array shape wraps the call itself in @().
    function Convert-Playbook {
        [CmdletBinding()]
        param ($Groups, $StigName = 'WindowsServer-2022-MS', $StigId = '', $OrganizationalSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Groups = $Groups; StigName = $StigName; StigId = $StigId; OrganizationalSetting = $OrganizationalSetting
        } {
            param ($Groups, $StigName, $StigId, $OrganizationalSetting)
            @($Groups | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $StigId -OrganizationalSetting $OrganizationalSetting)
        }
    }

    function New-AccountPolicyRule {
        param ($Id = 'V-100')

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = ''
            PolicyName = 'Maximum password age'; PolicyValue = '60'; OrganizationValueRequired = $false
        }
    }

    function New-NxServiceRule {
        param ($Id = 'V-200')

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = ''
            Name = 'kdump'; Enabled = 'False'; State = ''
        }
    }
}

Describe 'ConvertTo-AnsiblePlaybook' {

    Context 'a rule type with a matching adapter' {

        It 'strips the trailing Rule off the PowerStigRule name to find the adapter' {
            # AccountPolicyRule -> Build-AnsibleAccountPolicyTask; success proves the name was
            # struck correctly, since a wrong name finds no adapter at all and warns instead.
            $result = @(Convert-Playbook -Groups @(New-RuleGroup 'AccountPolicyRule' @(New-AccountPolicyRule)) -WarningAction Stop)

            $result.Count | Should-Be 1
            $result[0].Task.name | Should-Be 'V-100 | MEDIUM | Maximum password age'
        }

        It 'converts every rule in the group, not only the first' {
            $result = @(Convert-Playbook -Groups @(New-RuleGroup 'AccountPolicyRule' @(
                (New-AccountPolicyRule -Id 'V-100'), (New-AccountPolicyRule -Id 'V-101')
            )) -WarningAction Stop)

            $result.Count | Should-Be 2
        }

        It 'converts every group handed to it' {
            $result = @(Convert-Playbook -Groups @(
                (New-RuleGroup 'AccountPolicyRule' @(New-AccountPolicyRule -Id 'V-100'))
                (New-RuleGroup 'AccountPolicyRule' @(New-AccountPolicyRule -Id 'V-101'))
            ) -WarningAction Stop)

            $result.Count | Should-Be 2
        }
    }

    Context 'a rule type with no matching adapter' {

        # Adding support for a rule type means adding one Build-Ansible<Type>Task function, so an
        # unknown type has to be survivable - warn and move on - rather than fatal.
        It 'warns which generator is missing' {
            $warnings = Convert-Playbook -Groups @(New-RuleGroup 'ProcessMitigationRule' @([pscustomobject] @{ Id = 'V-900' })) 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $warnings.Message | Should-BeLikeString '*Build-AnsibleProcessMitigationTask is not currently supported*'
        }

        It 'produces no task for it' {
            $result = @(Convert-Playbook -Groups @(New-RuleGroup 'ProcessMitigationRule' @([pscustomobject] @{ Id = 'V-900' })) -WarningAction SilentlyContinue)

            $result.Count | Should-Be 0
        }
    }

    # RuleTypeOsFamily.psd1 names the OsFamily each adapter targets; a rule reaching dispatch for
    # a conversion of the other family is skipped rather than built anyway. See docs/adr/0010.
    Context 'a rule type whose adapter targets a different OsFamily' {

        It 'warns which adapter was skipped and why' {
            $warnings = Convert-Playbook -Groups @(New-RuleGroup 'AccountPolicyRule' @(New-AccountPolicyRule)) -StigName 'RHEL-9' 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $warnings.Message | Should-BeLikeString '*Build-AnsibleAccountPolicyTask targets Windows, not RedHat*'
        }

        # Every rule the skipped group carries, not only that the type was skipped - the same
        # reason ADR 0009's own skip-and-warn names the rule id.
        It 'names every rule id the skipped group carries' {
            $warnings = Convert-Playbook -Groups @(New-RuleGroup 'AccountPolicyRule' @(
                (New-AccountPolicyRule -Id 'V-100'), (New-AccountPolicyRule -Id 'V-101')
            )) -StigName 'RHEL-9' 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $warnings.Message | Should-BeLikeString '*V-100, V-101*'
        }

        It 'produces no task for it' {
            $result = @(Convert-Playbook -Groups @(New-RuleGroup 'AccountPolicyRule' @(New-AccountPolicyRule)) -StigName 'RHEL-9' -WarningAction SilentlyContinue)

            $result.Count | Should-Be 0
        }

        It 'skips a Linux-only adapter for a Windows conversion the same way' {
            $result = @(Convert-Playbook -Groups @(New-RuleGroup 'nxServiceRule' @(New-NxServiceRule)) -WarningAction SilentlyContinue)

            $result.Count | Should-Be 0
        }
    }

    Context 'a rule type whose adapter targets the conversion''s own OsFamily' {

        It 'converts it, rather than skipping every Linux rule type' {
            $result = @(Convert-Playbook -Groups @(New-RuleGroup 'nxServiceRule' @(New-NxServiceRule)) -StigName 'RHEL-9' -WarningAction Stop)

            $result.Count | Should-Be 1
        }
    }

    # GeneratorCoverage.Tests.ps1 is what keeps every real adapter listed; this pins what happens
    # at runtime if one isn't - a table gap must not silently swallow an existing rule type.
    # See docs/adr/0010.
    Context 'a rule type missing from RuleTypeOsFamily.psd1' {

        It 'is not restricted, and converts normally' {
            $result = @(InModuleScope -ModuleName PowerStigConverter -Parameters @{
                Groups = @(New-RuleGroup 'AccountPolicyRule' @(New-AccountPolicyRule))
            } {
                param ($Groups)
                $saved = $script:ruleTypeOsFamily
                $script:ruleTypeOsFamily = @{}
                try {
                    @($Groups | ConvertTo-AnsiblePlaybook -StigName 'RHEL-9' -StigId '' -OrganizationalSetting @{} -WarningAction Stop)
                }
                finally {
                    $script:ruleTypeOsFamily = $saved
                }
            })

            $result.Count | Should-Be 1
        }
    }
}
