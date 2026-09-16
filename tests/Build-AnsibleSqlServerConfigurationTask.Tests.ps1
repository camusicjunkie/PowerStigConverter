#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    # The shape every SqlServerConfiguration rule has in both STIGs: two fields, the value always
    # the string '0' or '1', and OrganizationValueRequired false throughout.
    function New-SqlServerConfigurationRule {
        param (
            $Id = 'V-214034',
            $Severity = 'medium',
            $OptionName = 'filestream access level',
            $OptionValue = '0'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            OptionName = $OptionName
            OptionValue = $OptionValue
            OrganizationValueRequired = $false
        }
    }

    function Get-SqlServerConfigurationItem {
        param ($Rule)

        Invoke-Generator -Generator 'Build-AnsibleSqlServerConfigurationTask' -Rule $Rule `
            -StigName 'SqlServer-2016-Instance'
    }
}

# One win_dsc task per rule over the role-scoped instance list. No organization value - neither
# org.default.xml declares a slot for any of these ids - and no handler, OptionName being part of
# the resource key and unique within each STIG. See #66.
Describe 'Build-AnsibleSqlServerConfigurationTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSqlServerConfigurationTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'SqlServer-2016-Instance' `
        -Factory { New-SqlServerConfigurationRule }

    Context 'the task it builds' {

        BeforeAll {
            $script:item = Get-SqlServerConfigurationItem -Rule (New-SqlServerConfigurationRule)
            $script:dsc = $item.Task.'ansible.windows.win_dsc'
        }

        # SqlServerDsc renamed the resource in v15; the adapter keeps the rule type's pre-v15 name
        # because ConvertTo-AnsibleTask derives it from the rule type. The one place the two names
        # diverge, so this pins the emitted one.
        It 'uses the SqlConfiguration DSC resource, not the rule type''s name' {
            $dsc.resource_name | Should-Be 'SqlConfiguration'
        }

        # Item 2.
        It 'maps the option name off the rule' {
            $dsc.OptionName | Should-Be 'filestream access level'
        }

        # PowerStig carries the value as a string and powershell-yaml would quote it, which the
        # SInt32 property will not take - so the cast is the assertion, not the number.
        It 'maps the option value off the rule as a number' {
            $dsc.OptionValue | Should-Be 0
            $dsc.OptionValue | Should-HaveType ([int])
        }

        # The options these rules set are inert until the instance restarts and the resource
        # defaults RestartService off, so a write without it reports changed and leaves the
        # instance non-compliant.
        It 'asks the resource to restart the instance' {
            $dsc.RestartService | Should-BeTrue
            $dsc.RestartService | Should-HaveType ([bool])
        }

        # ServerName, the credential and RestartTimeout are omitted deliberately: the resource's
        # own defaults are about the target, which is where win_dsc already runs. See #66.
        It 'passes only the resource name, the instance, the option and the restart' {
            @($dsc.Keys) |
                Should-BeCollection @('resource_name', 'InstanceName', 'OptionName', 'OptionValue', 'RestartService')
        }

        # The instance is the one thing the rule cannot supply, so it loops a role-scoped list
        # rather than being named per rule.
        It 'loops the role''s instance list, naming each instance bare' {
            $item.Task.loop | Should-Be '{{ stig_sqlserver_2016_instance_instances }}'
            $dsc.InstanceName | Should-Be '{{ item }}'
        }

        It 'guards the task with the rule''s own toggle, no block' {
            $item.Task.when | Should-Be 'stig_sqlserver_2016_instance_214034_when'
            $item.Task.block | Should-BeNull
        }

        # Imperative, like Build-AnsibleRegistryTask: "Ensure common criteria compliance enabled
        # is 1" reads badly against option names that already end in a verb.
        It 'names the task for <Id>, its severity and the option it sets' -ForEach @(
            @{
                Id = 'V-214034'; Severity = 'medium'
                OptionName = 'filestream access level'; OptionValue = '0'
                Expected = 'V-214034 | MEDIUM | Set filestream access level to 0'
            }
            @{
                Id = 'V-213975'; Severity = 'medium'
                OptionName = 'common criteria compliance enabled'; OptionValue = '1'
                Expected = 'V-213975 | MEDIUM | Set common criteria compliance enabled to 1'
            }
        ) {
            $rule = New-SqlServerConfigurationRule -Id $Id -Severity $Severity `
                -OptionName $OptionName -OptionValue $OptionValue

            (Get-SqlServerConfigurationItem -Rule $rule).Task.name | Should-Be $Expected
        }
    }

    # Item 9. The generator's RoleVariable is the single source for the reference the task loops
    # and the declaration defaults/ carries. See #57 and docs/adr/0004.
    Context 'the role variables it declares' {

        It 'declares the same list the task loops' {
            $item = Get-SqlServerConfigurationItem -Rule (New-SqlServerConfigurationRule)

            $item.RoleVariable | Should-Be 'instances'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'SqlServer-2016-Instance' |
                Should-ContainCollection @('stig_sqlserver_2016_instance_instances: []')
            $item.Task.loop | Should-Be '{{ stig_sqlserver_2016_instance_instances }}'
        }
    }
}
