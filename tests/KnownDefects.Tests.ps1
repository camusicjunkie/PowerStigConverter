#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Failing tests for defects found while characterising the module. Each one states the
    behaviour the module is supposed to have, and each one is red against the current code.

    They are tagged KnownDefect so the rest of the suite can be run green:

        ./Invoke-Tests.ps1              # the suite as it stands
        ./Invoke-Tests.ps1 -Defects     # just the outstanding defects

    As each defect is fixed, move its test into the test file for the function it belongs to
    and drop the tag.
#>

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'
}

Describe 'Get-AnsibleOrganizationValue' -Tag KnownDefect {

    # Source/Private/Get-AnsibleOrganizationValue.ps1 looks the option up as
    #     $data[$attributeName]['Option'][$orgValue]
    # where $orgValue is the literal property name 'OptionValue'. The Option table is keyed by
    # the rule's value - Enabled, Disabled - so the lookup misses, and [int] $null makes every
    # such rule come out as 0. Disabled is right by accident; Enabled is silently inverted.
    # The fix is to index by $Rule.$orgValue.
    Context 'a security option whose value is Enabled' {

        It 'maps Enabled to the 1 the option table gives for it' {
            $value = InModuleScope -ModuleName PowerStigConverter {
                $rule = [pscustomobject] @{
                    Id = 'V-101'
                    OptionName = 'Accounts: Guest account status'
                    OptionValue = 'Enabled'
                    OrganizationValueRequired = $false
                }
                Get-AnsibleOrganizationValue -Rule $rule -RuleType SecurityOption -StigName 'WindowsServer-2022-MS'
            }

            $value | Should-Be 1
        }

        It 'still maps Disabled to 0' {
            $value = InModuleScope -ModuleName PowerStigConverter {
                $rule = [pscustomobject] @{
                    Id = 'V-101'
                    OptionName = 'Accounts: Guest account status'
                    OptionValue = 'Disabled'
                    OrganizationValueRequired = $false
                }
                Get-AnsibleOrganizationValue -Rule $rule -RuleType SecurityOption -StigName 'WindowsServer-2022-MS'
            }

            $value | Should-Be 0
        }
    }
}

Describe 'New-AnsibleIisLoggingTask' -Tag KnownDefect {

    # The generator reads $logging.LogTargetW3C and $logging.LogCustomFieldEntry, but
    # Get-AnsibleOrganizationValue returns those two properties under the names LogTarget and
    # LogCustomFields. Both reads come back null, so the DSC task silently loses the log
    # target and the custom fields. Either the producer or the consumer has to be renamed.
    Context 'a rule that specifies where IIS logs go' {

        BeforeAll {
            $script:task = InModuleScope -ModuleName PowerStigConverter {
                $rule = [pscustomobject] @{
                    Id = 'V-300'
                    Severity = 'medium'
                    DuplicateOf = ''
                    OrganizationValueRequired = $false
                    LogFlags = 'Date,Time,ClientIP'
                    LogFormat = 'W3C'
                    LogPeriod = 'Daily'
                    LogTargetW3C = 'File,ETW'
                    LogCustomFieldEntry = ''
                }
                ($rule | New-AnsibleIisLoggingTask -StigName 'IISServer-10.0').Task
            }
        }

        It 'carries the log target through to the DSC task' {
            $task.'ansible.windows.win_dsc'.LogTargetW3C | Should-BeCollection @('File', 'ETW')
        }

        It 'still carries the properties whose names already line up' {
            $task.'ansible.windows.win_dsc'.LogFormat | Should-Be 'W3C'
            $task.'ansible.windows.win_dsc'.LogPeriod | Should-Be 'Daily'
        }
    }
}

Describe 'Export-AnsibleConditionalValue' -Tag KnownDefect {

    # The task generators skip duplicate rules, and ConvertTo-AnsiblePlaybook skips rule types
    # with no generator. Export-AnsibleConditionalValue does neither: it walks the raw rule
    # list, so the defaults files declare a _when toggle for rules that have no task. The
    # generated defaults then do not match the generated tasks, and the role ships variables
    # that do nothing.
    Context 'rules that never became tasks' {

        BeforeAll {
            $script:defaultsPath = Join-Path $TestDrive 'defects'
            $script:role = New-AnsiblePlaybook -StigName 'WindowsServer-2022-MS' -Path $fixtureRoot `
                -OutputPath $defaultsPath -RoleName 'defect_role' -WarningAction SilentlyContinue 6>$null
        }

        It 'does not declare a toggle for a rule marked as a duplicate' {
            Get-Content -Path (Join-Path $role.DefaultPath 'main_default_cat1.yml') -Raw |
                Should-NotBeLikeString '*_107_when*'
        }

        It 'does not declare a toggle for a rule type with no generator' {
            Get-Content -Path (Join-Path $role.DefaultPath 'main_default_cat2.yml') -Raw |
                Should-NotBeLikeString '*_110_when*'
        }
    }
}

Describe 'New-AnsiblePlaybook' -Tag KnownDefect {

    # New-AnsiblePlaybook takes -Path and hands it to Get-PowerStigFile and to
    # Export-AnsibleOrganizationValue, but the task generators reach the org settings through
    # Get-AnsibleOrganizationValue, which calls Get-PowerStigFile -Type Org with no -Path at
    # all. Organisation values are therefore always read from LOCALAPPDATA, whatever -Path
    # said. Any STIG data kept elsewhere generates tasks with the value missing, and the
    # code path cannot be tested without depending on what is on the machine.
    Context 'a STIG whose rules need an organisation value' {

        It 'resolves the organisation value from the STIG data path it was given' {
            $role = New-AnsiblePlaybook -StigName 'WindowsClient-11' -Path $fixtureRoot `
                -OutputPath (Join-Path $TestDrive 'orgpath') -RoleName 'orgpath_role' `
                -WarningAction SilentlyContinue 6>$null

            # The fixture org settings file sets V-201, so the task should reference the role
            # variable that carries it rather than being emitted with an empty value.
            Get-Content -Path (Join-Path $role.TaskPath 'cat2.yml') -Raw |
                Should-BeLikeString '*stig_client_11_201_account_lockout_duration*'
        }
    }
}
