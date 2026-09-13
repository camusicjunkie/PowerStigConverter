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

    # RoleVariableData.psd1 gives a rule type either scope. No shipped rule type declares a
    # role-scoped one yet - SslSettings and WebAppPool are the first - so these state the entry
    # rather than waiting on them.
    Context 'a role variable declared once for the whole role' {

        BeforeAll {
            InModuleScope -ModuleName PowerStigConverter {
                $script:roleVariableDataBefore = $script:roleVariableData
                $script:roleVariableData = @{ AccountPolicy = @{ PerRole = @('websites') } }
            }
        }

        AfterAll {
            InModuleScope -ModuleName PowerStigConverter {
                $script:roleVariableData = $script:roleVariableDataBefore
            }
        }

        It 'declares it as an empty list, carrying no rule id' {
            $rule = [pscustomobject] @{
                Id = 'V-100'; PolicyName = 'Maximum password age'; PolicyValue = '60'
                DuplicateOf = ''; OrganizationValueRequired = $false
            }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' @($rule))).main_default_org

            $content | Should-ContainCollection @('stig_server_2022_websites: []')
        }

        # Every rule of the type reads the same one, so it arrives once per rule and must still
        # be declared once.
        It 'declares it once however many rules of the type there are' {
            $rules = 'V-100', 'V-101' | ForEach-Object {
                [pscustomobject] @{
                    Id = $_; PolicyName = 'Maximum password age'; PolicyValue = '60'
                    DuplicateOf = ''; OrganizationValueRequired = $false
                }
            }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' $rules)).main_default_org

            @($content | Where-Object { $_ -eq 'stig_server_2022_websites: []' }).Count | Should-Be 1
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

    # No org settings attribute feeds the site name either, so a site-scoped IIS task references
    # a role variable the site fills in, the same way the log path does. See docs/adr/0004.
    Context 'the IIS website' {

        It 'declares it blank for every WebConfigurationProperty rule' {
            $rule = [pscustomobject] @{ Id = 'V-310'; DuplicateOf = ''; OrganizationValueRequired = $false }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'WebConfigurationPropertyRule' @($rule)) `
                -StigName 'IISServer-10.0').main_default_org

            $content | Should-ContainCollection @('stig_iisserver_10_0_310_website: ')
        }

        It 'declares it blank for every MimeType rule' {
            $rule = [pscustomobject] @{ Id = 'V-311'; DuplicateOf = ''; OrganizationValueRequired = $false }

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'MimeTypeRule' @($rule)) `
                -StigName 'IISServer-10.0').main_default_org

            $content | Should-ContainCollection @('stig_iisserver_10_0_311_website: ')
        }
    }
}
