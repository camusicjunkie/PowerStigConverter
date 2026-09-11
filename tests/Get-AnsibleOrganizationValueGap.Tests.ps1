#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Get-Gap {
        param ($Rule, $RuleType, $OrgSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rule = $Rule; RuleType = $RuleType; OrgSetting = $OrgSetting
        } {
            param ($Rule, $RuleType, $OrgSetting)
            Get-AnsibleOrganizationValueGap -Rule $Rule -RuleType $RuleType -OrgSetting $OrgSetting
        }
    }

    # Builds an org settings map the way Get-PowerStigOrgSetting would, from a node written out
    # as the org settings file writes it.
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

Describe 'Get-AnsibleOrganizationValueGap' {

    Context 'a setting the organization has answered' {

        It 'reports no gap' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }
            $orgSetting = New-OrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />'

            @(Get-Gap -Rule $rule -RuleType AccountPolicy -OrgSetting $orgSetting).Count | Should-Be 0
        }
    }

    # PowerStig ships these blank on purpose: they are policy questions only the adopting
    # organization can answer, and until it does there is no value to write into the role.
    Context 'a setting that is present but blank' {

        It 'reports it as unanswered, naming the field' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }
            $orgSetting = New-OrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />'

            $gap = @(Get-Gap -Rule $rule -RuleType AccountPolicy -OrgSetting $orgSetting)

            $gap.Count | Should-Be 1
            $gap[0].RuleId | Should-Be 'V-100'
            $gap[0].RuleType | Should-Be 'AccountPolicy'
            $gap[0].Field | Should-Be 'PolicyValue'
            $gap[0].Reason | Should-Be 'Unanswered'
        }

        It 'treats whitespace as unanswered, since it is no more an answer than an empty string' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }
            $orgSetting = New-OrgSetting '<OrganizationalSetting id="V-100" PolicyValue="   " />'

            @(Get-Gap -Rule $rule -RuleType AccountPolicy -OrgSetting $orgSetting).Reason |
                Should-Be 'Unanswered'
        }
    }

    # A different fault with a different remedy: fill the value in, versus fetch an org settings
    # file that matches the STIG version in hand.
    Context 'a rule the org settings file has no entry for' {

        It 'reports it as missing rather than unanswered' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }

            $gap = @(Get-Gap -Rule $rule -RuleType AccountPolicy -OrgSetting @{})

            $gap.Count | Should-Be 1
            $gap[0].RuleId | Should-Be 'V-100'
            $gap[0].Reason | Should-Be 'Missing'
        }
    }

    # The check used to look at one designated field per rule type while the task consumed more
    # than one, so a service with no startup type passed and produced a half-empty task.
    Context 'a rule type whose task needs more than one field' {

        It 'reports the blank field when the designated one is filled in' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }
            $orgSetting = New-OrgSetting '<OrganizationalSetting id="V-248" ServiceName="WinDefend" StartupType="" />'

            $gap = @(Get-Gap -Rule $rule -RuleType Service -OrgSetting $orgSetting)

            $gap.Count | Should-Be 1
            $gap[0].Field | Should-Be 'StartupType'
        }

        It 'reports every blank field, not just the first' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }
            $orgSetting = New-OrgSetting '<OrganizationalSetting id="V-248" ServiceName="" StartupType="" />'

            @(Get-Gap -Rule $rule -RuleType Service -OrgSetting $orgSetting).Field |
                Should-BeCollection @('ServiceName', 'StartupType')
        }

        # New-AnsibleIisLoggingTask already omits LogCustomFields from the DSC task when it is
        # empty, so requiring it would refuse a conversion that has everything it needs.
        It 'does not require a field the task treats as optional' {
            $rule = [pscustomobject] @{ Id = 'V-300'; OrganizationValueRequired = $true }
            $orgSetting = New-OrgSetting ('<OrganizationalSetting id="V-300" LogFlags="Date,Time" ' +
                'LogFormat="W3C" LogPeriod="Daily" LogTargetW3C="File,ETW" LogCustomFieldEntry="" />')

            @(Get-Gap -Rule $rule -RuleType IisLogging -OrgSetting $orgSetting).Count | Should-Be 0
        }
    }

    # A gap only matters if the rule would have produced a task. These two never do, so failing
    # the conversion over them would refuse a role that had everything it needed.
    Context 'rules that produce no task' {

        It 'ignores a rule that carries its own value' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $false }

            @(Get-Gap -Rule $rule -RuleType AccountPolicy -OrgSetting @{}).Count | Should-Be 0
        }

        It 'ignores a duplicate, which the rule it points at already covers' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                OrganizationValueRequired = $true
                DuplicateOf = 'V-099'
            }

            @(Get-Gap -Rule $rule -RuleType AccountPolicy -OrgSetting @{}).Count | Should-Be 0
        }
    }
}
