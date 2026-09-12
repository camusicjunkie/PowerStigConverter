#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-RuleGroup {
        param ($PowerStigRule, $Rules)

        [pscustomobject] @{ PowerStigRule = $PowerStigRule; StigRule = $Rules }
    }

    function Export-OrgValues {
        param ($Groups, $OrganizationalSetting = @{}, $StigName = 'WindowsServer-2022-MS')

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Groups = $Groups; OrganizationalSetting = $OrganizationalSetting; StigName = $StigName
        } {
            param ($Groups, $OrganizationalSetting, $StigName)
            $Groups | Export-AnsibleOrganizationValue -StigName $StigName -OrganizationalSetting $OrganizationalSetting
        }
    }
}

Describe 'Export-AnsibleOrganizationValue' {

    Context 'the severity toggles tasks/main.yml imports on' {

        It 'declares all three, defaulted on' {
            $content = (Export-OrgValues -Groups @()).main_default_org -join "`n"

            $content | Should-BeLikeString '*stig_server_2022_cat1: true*'
            $content | Should-BeLikeString '*stig_server_2022_cat2: true*'
            $content | Should-BeLikeString '*stig_server_2022_cat3: true*'
        }
    }

    Context 'a value the organization decides' {

        It 'declares it with the answer from the org settings file' {
            $rule = [pscustomobject] @{
                Id = 'V-100'; PolicyName = 'Account lockout duration'
                DuplicateOf = ''; OrganizationValueRequired = $true
            }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />'

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' @($rule)) `
                -OrganizationalSetting $orgSetting).main_default_org

            $content | Should-ContainCollection @('stig_server_2022_100_account_lockout_duration: 15')
        }

        It 'declares it with no value when nobody has answered' {
            $rule = [pscustomobject] @{
                Id = 'V-100'; PolicyName = 'Account lockout duration'
                DuplicateOf = ''; OrganizationValueRequired = $true
            }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />'

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' @($rule)) `
                -OrganizationalSetting $orgSetting).main_default_org

            $content | Should-ContainCollection @('stig_server_2022_100_account_lockout_duration: ')
        }
    }

    Context 'rules that declare nothing' {

        It 'declares no variable for a rule carrying its own value' {
            $rule = [pscustomobject] @{
                Id = 'V-100'; PolicyName = 'Maximum password age'; PolicyValue = '60'
                DuplicateOf = ''; OrganizationValueRequired = $false
            }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' @($rule))).main_default_org -join "`n"

            $content | Should-NotBeLikeString '*maximum_password_age*'
        }

        It 'declares no variable for a duplicate' {
            $rule = [pscustomobject] @{
                Id = 'V-100'; PolicyName = 'Account lockout duration'
                DuplicateOf = 'V-099'; OrganizationValueRequired = $true
            }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' @($rule))).main_default_org -join "`n"

            $content | Should-NotBeLikeString '*account_lockout_duration*'
        }

        It 'ignores a rule type OrganizationData.psd1 says nothing about' {
            $rule = [pscustomobject] @{ Id = 'V-110'; DuplicateOf = ''; OrganizationValueRequired = $true }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'ProcessMitigationRule' @($rule))).main_default_org -join "`n"

            $content | Should-NotBeLikeString '*V-110*'
        }
    }

    # No org settings attribute feeds the IIS log path, so it is a role variable the site fills in
    # rather than an organization value. See docs/adr/0004.
    Context 'the IIS log path' {

        It 'declares it blank for every IisLogging rule, answered or not' {
            $rule = [pscustomobject] @{ Id = 'V-300'; DuplicateOf = ''; OrganizationValueRequired = $false }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'IisLoggingRule' @($rule)) `
                -StigName 'IISServer-10.0').main_default_org

            $content | Should-ContainCollection @('stig_iisserver_10_0_300_logpath: ')
        }
    }
}
