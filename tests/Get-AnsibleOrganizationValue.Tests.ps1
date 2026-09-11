#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'

    function Get-OrgValue {
        param ($Rule, $RuleType, $StigName, $OrgSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rule = $Rule; RuleType = $RuleType; StigName = $StigName; OrgSetting = $OrgSetting
        } {
            param ($Rule, $RuleType, $StigName, $OrgSetting)
            Get-AnsibleOrganizationValue -Rule $Rule -RuleType $RuleType -StigName $StigName -OrgSetting $OrgSetting
        }
    }

    # The org settings file is read once up front and handed round as a map, so a test that
    # needs one loads it the same way New-AnsiblePlaybook does.
    function Get-OrgSetting {
        param ($StigName, $Path)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ StigName = $StigName; Path = $Path } {
            param ($StigName, $Path)
            Get-PowerStigOrgSetting -StigName $StigName -Path $Path
        }
    }
}

Describe 'Get-AnsibleOrganizationValue' {

    # Some STIG settings are expressed as Enabled or Disabled, but win_security_policy wants the
    # number the policy actually takes. The lookup tables in SecurityOptionData.psd1 and
    # AccountPolicyData.psd1 hold that mapping, keyed by the value the rule asks for.
    Context 'a setting expressed as Enabled or Disabled' {

        It 'maps <OptionValue> to <Expected>' -ForEach @(
            @{ OptionValue = 'Enabled'; Expected = 1 }
            @{ OptionValue = 'Disabled'; Expected = 0 }
        ) {
            $rule = [pscustomobject] @{
                Id = 'V-101'
                OptionName = 'Accounts: Guest account status'
                OptionValue = $OptionValue
                OrganizationValueRequired = $false
            }

            Get-OrgValue -Rule $rule -RuleType SecurityOption -StigName 'WindowsServer-2022-MS' |
                Should-Be $Expected
        }

        It 'looks the mapping up by the value asked for, not by the name of the property' {
            # Indexing the table by the property name instead misses every time, and the [int]
            # cast then turns the miss into 0 - which is indistinguishable from a real Disabled.
            $enabled = [pscustomobject] @{
                Id = 'V-101'
                OptionName = 'Accounts: Guest account status'
                OptionValue = 'Enabled'
                OrganizationValueRequired = $false
            }
            $disabled = [pscustomobject] @{
                Id = 'V-101'
                OptionName = 'Accounts: Guest account status'
                OptionValue = 'Disabled'
                OrganizationValueRequired = $false
            }

            $enabledValue = Get-OrgValue -Rule $enabled -RuleType SecurityOption -StigName 'WindowsServer-2022-MS'
            $disabledValue = Get-OrgValue -Rule $disabled -RuleType SecurityOption -StigName 'WindowsServer-2022-MS'

            $enabledValue | Should-NotBe $disabledValue
        }
    }

    Context 'a setting that carries its own value' {

        It 'passes the value straight through' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Maximum password age'
                PolicyValue = '60'
                OrganizationValueRequired = $false
            }

            Get-OrgValue -Rule $rule -RuleType AccountPolicy -StigName 'WindowsServer-2022-MS' |
                Should-Be '60'
        }
    }

    # These two types are reported as an object rather than a scalar, because the task needs
    # more than one field from them. The property names are the contract the matching task
    # generator reads, so they are pinned here.
    Context 'settings made of more than one field' {

        It 'reports a service as its name and startup type' {
            $rule = [pscustomobject] @{
                Id = 'V-248'
                ServiceName = 'WinDefend'
                StartupType = 'Automatic'
                OrganizationValueRequired = $false
            }

            $service = Get-OrgValue -Rule $rule -RuleType Service -StigName 'WindowsServer-2022-MS'

            $service.ServiceName | Should-Be 'WinDefend'
            $service.StartupType | Should-Be 'Automatic'
        }

        It 'reports IIS logging under the names the task generator reads' {
            $rule = [pscustomobject] @{
                Id = 'V-300'
                LogFlags = 'Date,Time'
                LogFormat = 'W3C'
                LogPeriod = 'Daily'
                LogTargetW3C = 'File,ETW'
                LogCustomFieldEntry = ''
                OrganizationValueRequired = $false
            }

            $logging = Get-OrgValue -Rule $rule -RuleType IisLogging -StigName 'IISServer-10.0'

            $logging.LogFlags | Should-Be 'Date,Time'
            $logging.LogFormat | Should-Be 'W3C'
            $logging.LogPeriod | Should-Be 'Daily'
            $logging.LogTarget | Should-Be 'File,ETW'
            $logging.PSObject.Properties.Name | Should-ContainCollection @('LogCustomFields')
        }
    }

    # Where the STIG leaves the value to the implementing site, the task cannot hardcode it.
    # It gets a reference to a role variable instead, and the value the org settings file holds
    # becomes that variable's default.
    Context 'a setting the site has to decide' {

        BeforeAll {
            # Matches V-201 in the WindowsClient-11 fixture, whose org settings set it to 15.
            $script:orgRule = [pscustomobject] @{
                Id = 'V-201'
                PolicyName = 'Account lockout duration'
                PolicyValue = ''
                OrganizationValueRequired = $true
            }
        }

        It 'renders a reference to the role variable rather than a literal' {
            $orgSetting = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            Get-OrgValue -Rule $orgRule -RuleType AccountPolicy -StigName 'WindowsClient-11' -OrgSetting $orgSetting |
                Should-Be '{{ stig_client_11_201_account_lockout_duration }}'
        }
    }

    # An unanswered setting normally stops the conversion before it reaches here - see
    # New-AnsiblePlaybook - so by the time this function sees one, the caller has either been
    # told or has asked for blanks on purpose. It reports the gap by emitting nothing, and does
    # not warn a second time about something already reported.
    Context 'a setting the organization has not answered yet' {

        It 'emits nothing for an unanswered setting' {
            # Matches V-202 in the fixture, whose org settings value is deliberately empty.
            $rule = [pscustomobject] @{
                Id = 'V-202'
                PolicyName = 'Account lockout threshold'
                PolicyValue = ''
                OrganizationValueRequired = $true
            }
            $orgSetting = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            $values = Get-OrgValue -Rule $rule -RuleType AccountPolicy -StigName 'WindowsClient-11' -OrgSetting $orgSetting

            @($values).Count | Should-Be 0
        }

        It 'emits nothing for a setting the org settings file has no entry for at all' {
            $rule = [pscustomobject] @{
                Id = 'V-999'
                PolicyName = 'Account lockout threshold'
                PolicyValue = ''
                OrganizationValueRequired = $true
            }
            $orgSetting = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            $values = Get-OrgValue -Rule $rule -RuleType AccountPolicy -StigName 'WindowsClient-11' -OrgSetting $orgSetting

            @($values).Count | Should-Be 0
        }
    }
}
