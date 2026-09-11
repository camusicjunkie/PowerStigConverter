#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'

    # One entry point answers every question about a rule's organization values, so every test
    # here crosses the same seam and reads whichever answer it is about off the result.
    function Resolve-OrgValue {
        param ($Rule, $RuleType, $StigName = 'WindowsServer-2022-MS', $OrganizationalSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rule = $Rule; RuleType = $RuleType; StigName = $StigName; OrganizationalSetting = $OrganizationalSetting
        } {
            param ($Rule, $RuleType, $StigName, $OrganizationalSetting)
            Resolve-AnsibleOrganizationValue -Rule $Rule -RuleType $RuleType -StigName $StigName `
                -OrganizationalSetting $OrganizationalSetting
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

Describe 'Resolve-AnsibleOrganizationValue' {

    Context 'a rule type the module does not describe' {

        # OrganizationData.psd1 is the list of rule types, rather than a ValidateSet copied into
        # every signature that takes one, so adding a type is one edit in one file.
        It 'refuses a rule type OrganizationData.psd1 has no entry for' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $false }

            { Resolve-OrgValue -Rule $rule -RuleType 'AuditPolicy' } | Should -Throw
        }
    }
}

Describe 'Resolve-AnsibleOrganizationValue: the value the task consumes' {

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

            (Resolve-OrgValue -Rule $rule -RuleType SecurityOption).Value | Should-Be $Expected
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

            $enabledValue = (Resolve-OrgValue -Rule $enabled -RuleType SecurityOption).Value
            $disabledValue = (Resolve-OrgValue -Rule $disabled -RuleType SecurityOption).Value

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

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy).Value | Should-Be '60'
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

            $service = (Resolve-OrgValue -Rule $rule -RuleType Service).Value

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

            $logging = (Resolve-OrgValue -Rule $rule -RuleType IisLogging -StigName 'IISServer-10.0').Value

            # LogFlags and LogTargetW3C are lists to the DSC resource, so they arrive split.
            $logging.LogFlags -join '|' | Should-Be 'Date|Time'
            $logging.LogFormat | Should-Be 'W3C'
            $logging.LogPeriod | Should-Be 'Daily'
            $logging.LogTarget -join '|' | Should-Be 'File|ETW'
            $logging.PSObject.Properties.Name | Should-ContainCollection @('LogCustomFields')
        }
    }

    # Where the STIG leaves the value to the implementing site, the task cannot hardcode it.
    # It gets a reference to a role variable instead, and the value the org settings file holds
    # becomes that variable's default.
    Context 'a setting the site has to decide' {

        It 'renders a reference to the role variable rather than a literal' {
            # Matches V-201 in the WindowsClient-11 fixture, whose org settings set it to 15.
            $rule = [pscustomobject] @{
                Id = 'V-201'
                PolicyName = 'Account lockout duration'
                PolicyValue = ''
                OrganizationValueRequired = $true
            }
            $orgSetting = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -StigName 'WindowsClient-11' `
                -OrganizationalSetting $orgSetting).Value |
                Should-Be '{{ stig_client_11_201_account_lockout_duration }}'
        }
    }

    # An unanswered setting normally stops the conversion before a task is built - see
    # New-AnsiblePlaybook - so a generator only sees one when the caller asked for blanks on
    # purpose. The reference is still emitted: the variable is declared blank in defaults/, an
    # assert guards it, and the operator finishes the role by filling that one file in rather
    # than regenerating. Returning nothing instead is what used to leave defaults/ declaring a
    # variable that no task referenced.
    Context 'a setting the organization has not answered yet' {

        It 'still references the variable, so filling defaults/ in finishes the role' {
            # Matches V-202 in the fixture, whose org settings value is deliberately empty.
            $rule = [pscustomobject] @{
                Id = 'V-202'
                PolicyName = 'Account lockout threshold'
                PolicyValue = ''
                OrganizationValueRequired = $true
            }
            $orgSetting = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -StigName 'WindowsClient-11' `
                -OrganizationalSetting $orgSetting).Value |
                Should-Be '{{ stig_client_11_202_account_lockout_threshold }}'
        }

        It 'references the variable even when the org settings file has no entry at all' {
            $rule = [pscustomobject] @{
                Id = 'V-999'
                PolicyName = 'Account lockout threshold'
                PolicyValue = ''
                OrganizationValueRequired = $true
            }
            $orgSetting = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -StigName 'WindowsClient-11' `
                -OrganizationalSetting $orgSetting).Value |
                Should-Be '{{ stig_client_11_999_account_lockout_threshold }}'
        }
    }

    # Three org values are lists rather than scalars. They are split here so that both halves of
    # the resolution hand back the same shape, and so the generator never has to split a value
    # that might be a variable reference - '{{ x }}' -split ',' is a one element list, which is
    # what used to reach win_user_right for an org-valued identity.
    Context 'a setting the task needs as a list' {

        It 'splits an identity list the rule carries itself' {
            $rule = [pscustomobject] @{
                Id = 'V-104'
                DisplayName = 'Access this computer from the network'
                Identity = 'Administrators,Authenticated Users'
                OrganizationValueRequired = $false
            }

            $identity = (Resolve-OrgValue -Rule $rule -RuleType UserRight).Value

            $identity -join '|' | Should-Be 'Administrators|Authenticated Users'
        }

        It 'hands back one reference for an identity list the organization decides' {
            $rule = [pscustomobject] @{
                Id = 'V-104'
                DisplayName = 'Access this computer from the network'
                Identity = ''
                OrganizationValueRequired = $true
            }

            (Resolve-OrgValue -Rule $rule -RuleType UserRight).Value |
                Should-Be '{{ stig_server_2022_104_access_this_computer_from_the_network }}'
        }
    }
}

Describe 'Resolve-AnsibleOrganizationValue: the organization variables it declares' {

    # The declaration in defaults/, the reference the task interpolates and the assert that
    # guards it all come off the same resolved variable, so they cannot drift apart.
    Context 'a rule whose value the organization has answered' {

        BeforeAll {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                OrganizationValueRequired = $true
            }
            $script:variable = (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />')).Variable
        }

        It 'names the variable after the rule type name property, not the org node attribute' {
            $variable.Name | Should-Be 'stig_server_2022_100_account_lockout_duration'
        }

        It 'declares it in defaults/ with the answer from the org settings file' {
            $variable.Declaration | Should-Be 'stig_server_2022_100_account_lockout_duration: 15'
        }

        It 'references the same name the declaration uses' {
            $variable.Reference | Should-Be '{{ stig_server_2022_100_account_lockout_duration }}'
        }
    }

    # A type whose task needs several fields has no single name to call them all, so each
    # variable is named for its field instead.
    Context 'a rule type whose task needs more than one field' {

        It 'declares one variable per field' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }

            $variable = (Resolve-OrgValue -Rule $rule -RuleType Service `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-248" ServiceName="WinDefend" StartupType="Automatic" />')).Variable

            $variable.Name | Should-BeCollection @(
                'stig_server_2022_248_servicename'
                'stig_server_2022_248_startuptype'
            )
        }
    }

    # Reshaped here rather than on the host, because the shape the ansible module consumes
    # should be decided where a test can see it. See docs/adr/0003.
    Context 'values the ansible module needs in a different shape' {

        It 'splits a field the task needs as a list, so the variable holds a yaml sequence' {
            $rule = [pscustomobject] @{
                Id = 'V-104'
                DisplayName = 'Access this computer from the network'
                OrganizationValueRequired = $true
            }

            $variable = (Resolve-OrgValue -Rule $rule -RuleType UserRight `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-104" Identity="Administrators,Guests" />')).Variable

            $variable.Declaration |
                Should-Be 'stig_server_2022_104_access_this_computer_from_the_network: [Administrators, Guests]'
        }

        # PowerStig holds Cert:\LocalMachine\Root where win_certificate_info takes a store name
        # of Root.
        It 'reduces a certificate store path to the store name' {
            $rule = [pscustomobject] @{ Id = 'V-500'; OrganizationValueRequired = $true }

            $variable = (Resolve-OrgValue -Rule $rule -RuleType RootCertificate `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-500" Location="Cert:\LocalMachine\Root" />')).Variable

            $variable.Default | Should-Be 'Root'
        }
    }

    Context 'a rule that carries its own value' {

        It 'declares no variable, because the task inlines the value' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Maximum password age'
                PolicyValue = '60'
                OrganizationValueRequired = $false
            }

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy).Variable.Count | Should-Be 0
        }
    }
}

Describe 'Resolve-AnsibleOrganizationValue: the values the org settings file does not answer' {

    Context 'a setting the organization has answered' {

        It 'reports nothing incomplete' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />'

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -OrganizationalSetting $orgSetting).Incomplete.Count |
                Should-Be 0
        }
    }

    # PowerStig ships these blank on purpose: they are policy questions only the adopting
    # organization can answer, and until it does there is no value to write into the role.
    Context 'a setting that is present but unanswered' {

        It 'reports it as unanswered, naming the field' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />'

            $incomplete = (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -OrganizationalSetting $orgSetting).Incomplete

            $incomplete.Count | Should-Be 1
            $incomplete[0].RuleId | Should-Be 'V-100'
            $incomplete[0].RuleType | Should-Be 'AccountPolicy'
            $incomplete[0].Field | Should-Be 'PolicyValue'
            $incomplete[0].Status | Should-Be 'Unanswered'
        }

        It 'treats whitespace as unanswered, since it is no more an answer than an empty string' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="   " />'

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -OrganizationalSetting $orgSetting).Incomplete.Status |
                Should-Be 'Unanswered'
        }

        It 'declares the variable blank, for the operator to fill in' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                OrganizationValueRequired = $true
            }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />'

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy -OrganizationalSetting $orgSetting).Variable.Declaration |
                Should-Be 'stig_server_2022_100_account_lockout_duration: '
        }
    }

    # A different fault with a different remedy: fill the value in, versus fetch an org settings
    # file that matches the STIG version in hand.
    Context 'a rule the org settings file has no entry for' {

        It 'reports it as missing rather than unanswered' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $true }

            $incomplete = (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy).Incomplete

            $incomplete.Count | Should-Be 1
            $incomplete[0].RuleId | Should-Be 'V-100'
            $incomplete[0].Status | Should-Be 'Missing'
        }
    }

    # The check used to look at one designated field per rule type while the task consumed more
    # than one, so a service with no startup type passed and produced a half-empty task.
    Context 'a rule type whose task needs more than one field' {

        It 'reports the blank field when the designated one is filled in' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-248" ServiceName="WinDefend" StartupType="" />'

            $incomplete = (Resolve-OrgValue -Rule $rule -RuleType Service -OrganizationalSetting $orgSetting).Incomplete

            $incomplete.Count | Should-Be 1
            $incomplete[0].Field | Should-Be 'StartupType'
        }

        It 'reports every blank field, not just the first' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }
            $orgSetting = New-TestOrgSetting '<OrganizationalSetting id="V-248" ServiceName="" StartupType="" />'

            (Resolve-OrgValue -Rule $rule -RuleType Service -OrganizationalSetting $orgSetting).Incomplete.Field |
                Should-BeCollection @('ServiceName', 'StartupType')
        }

        # New-AnsibleIisLoggingTask already omits LogCustomFields from the DSC task when it is
        # empty, so requiring it would refuse a conversion that has everything it needs.
        It 'does not require a field the task treats as optional' {
            $rule = [pscustomobject] @{ Id = 'V-300'; OrganizationValueRequired = $true }
            $orgSetting = New-TestOrgSetting ('<OrganizationalSetting id="V-300" LogFlags="Date,Time" ' +
                'LogFormat="W3C" LogPeriod="Daily" LogTargetW3C="File,ETW" LogCustomFieldEntry="" />')

            (Resolve-OrgValue -Rule $rule -RuleType IisLogging -StigName 'IISServer-10.0' `
                -OrganizationalSetting $orgSetting).Incomplete.Count | Should-Be 0
        }
    }

    # An unanswered value only matters if the rule would have produced a task. These two never
    # do, so failing the conversion over them would refuse a role that had everything it needed.
    Context 'rules that produce no task' {

        It 'ignores a rule that carries its own value' {
            $rule = [pscustomobject] @{ Id = 'V-100'; OrganizationValueRequired = $false }

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy).Incomplete.Count | Should-Be 0
        }

        It 'ignores a duplicate, which the rule it points at already covers' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                OrganizationValueRequired = $true
                DuplicateOf = 'V-099'
            }

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy).Incomplete.Count | Should-Be 0
        }
    }
}

Describe 'Resolve-AnsibleOrganizationValue: the assert guarding an unanswered value' {

    # The conversion normally refuses outright, so these only appear in a role generated with
    # -AllowIncompleteOrganizationValue. They are what stops that role setting an empty value.
    Context 'a setting nobody has answered' {

        BeforeAll {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                OrganizationValueRequired = $true
            }
            $script:assert = (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />')).Assert
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

            $assert = (Resolve-OrgValue -Rule $rule -RuleType Service `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-248" ServiceName="WinDefend" StartupType="" />')).Assert

            $assert.'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_server_2022_248_startuptype | default("", true) | length > 0')
        }
    }

    # A rule the org settings file has no entry for needs all of its fields, since none of them
    # are there to be read.
    Context 'a rule with no entry at all' {

        It 'checks every field the rule type requires' {
            $rule = [pscustomobject] @{ Id = 'V-248'; OrganizationValueRequired = $true }

            $assert = (Resolve-OrgValue -Rule $rule -RuleType Service).Assert

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

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />')).Assert |
                Should-BeNull
        }

        It 'builds nothing for a rule that carries its own value' {
            $rule = [pscustomobject] @{
                Id = 'V-100'
                PolicyName = 'Account lockout duration'
                PolicyValue = '15'
                OrganizationValueRequired = $false
            }

            (Resolve-OrgValue -Rule $rule -RuleType AccountPolicy).Assert | Should-BeNull
        }
    }
}
