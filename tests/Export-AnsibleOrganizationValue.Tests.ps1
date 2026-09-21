#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-RuleGroup {
        param ($PowerStigRule, $Rules)

        [pscustomobject] @{ PowerStigRule = $PowerStigRule; StigRule = $Rules }
    }

    function Export-OrgValues {
        param ($Groups, $OrganizationalSetting = @{}, $StigName = 'WindowsServer-2022-MS', [string[]] $RoleVariable = @())

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Groups = $Groups; OrganizationalSetting = $OrganizationalSetting
            StigName = $StigName; RoleVariable = $RoleVariable
        } {
            param ($Groups, $OrganizationalSetting, $StigName, $RoleVariable)
            $Groups | Export-AnsibleOrganizationValue -StigName $StigName `
                -OrganizationalSetting $OrganizationalSetting -RoleVariable $RoleVariable
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

    # The role-scoped variables come in from the caller, derived from the tasks the generators
    # built, rather than from a rule-type table here: a table cannot tell that a Server STIG's IIS
    # rules reference no website. See #57.
    Context 'a role variable declared once for the whole role' {

        It 'declares it as an empty list, carrying no rule id' {
            $content = (Export-OrgValues -Groups @() -RoleVariable @('websites')).main_default_org

            $content | Should-ContainCollection @('stig_server_2022_websites: []')
        }

        It 'declares one line per name, however many rules referenced them' {
            $content = (Export-OrgValues -Groups @() -RoleVariable @('websites', 'webapppools')).main_default_org

            @($content | Where-Object { $_ -eq 'stig_server_2022_websites: []' }).Count | Should-Be 1
            $content | Should-ContainCollection @('stig_server_2022_webapppools: []')
        }

        It 'declares none when the tasks reference none' {
            $content = (Export-OrgValues -Groups @()).main_default_org -join "`n"

            $content | Should-NotBeLikeString '*websites*'
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

        # Dispatch skips this rule type for the same reason - declaring a variable here would be
        # one no generated task ever references. See docs/adr/0011.
        It 'declares no variable for a rule type whose adapter targets a different OsFamily' {
            $rule = [pscustomobject] @{
                Id = 'V-100'; PolicyName = 'Account lockout duration'
                DuplicateOf = ''; OrganizationValueRequired = $true
            }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />'

            $content = (Export-OrgValues -Groups @(New-RuleGroup 'AccountPolicyRule' @($rule)) `
                -OrganizationalSetting $orgSetting -StigName 'RHEL-9').main_default_org -join "`n"

            $content | Should-NotBeLikeString '*account_lockout_duration*'
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

    # The website used to be a per-rule variable declared by rule type, which meant an IISServer
    # role declared one per MimeType and WebConfigurationProperty rule that no task ever read.
    # It is role-scoped now and comes from the tasks, so the orphan cannot come back. See #57.
    Context 'the IIS website' {

        It 'declares no per-rule website for a <RuleType> rule' -ForEach @(
            @{ RuleType = 'WebConfigurationPropertyRule'; Id = 'V-310' }
            @{ RuleType = 'MimeTypeRule'; Id = 'V-311' }
        ) {
            $rule = [pscustomobject] @{ Id = $Id; DuplicateOf = ''; OrganizationValueRequired = $false }

            $content = (Export-OrgValues -Groups @(New-RuleGroup $RuleType @($rule)) `
                -StigName 'IISServer-10.0').main_default_org -join "`n"

            $content | Should-NotBeLikeString '*_website*'
        }
    }
}
