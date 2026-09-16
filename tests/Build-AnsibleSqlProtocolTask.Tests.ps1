#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    # V-213961 verbatim from SqlServer-2016-Instance-3.6, the one SqlProtocol rule in either STIG;
    # 2022-1.4 carries no SqlProtocolRule node at all.
    function New-SqlProtocolRule {
        param (
            $Id = 'V-213961',
            $Severity = 'medium',
            $ProtocolName = 'NamedPipes',
            $Enabled = 'False'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            ProtocolName = $ProtocolName
            Enabled = $Enabled
            OrganizationValueRequired = $false
        }
    }

    function Get-SqlProtocolItem {
        param ($Rule)

        Invoke-Generator -Generator 'Build-AnsibleSqlProtocolTask' -Rule $Rule -StigName 'SqlServer-2016-Instance'
    }
}

# SqlServerDsc's SqlProtocol keys on InstanceName and ProtocolName both, and the rule states the
# protocol - so unlike SqlLogin there is no second list to cross, and no shared handler either:
# the resource restarts the instance itself, cluster-aware, when it changes the setting. See #64.
Describe 'Build-AnsibleSqlProtocolTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSqlProtocolTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'SqlServer-2016-Instance' `
        -Factory { New-SqlProtocolRule }

    Context 'the task it builds' {

        BeforeAll {
            $script:item = Get-SqlProtocolItem -Rule (New-SqlProtocolRule)
            $script:dsc = $item.Task.'ansible.windows.win_dsc'
        }

        It 'uses the SqlProtocol DSC resource' {
            $dsc.resource_name | Should-Be 'SqlProtocol'
        }

        # Item 2.
        It 'maps the protocol name off the rule' {
            $dsc.ProtocolName | Should-Be 'NamedPipes'
        }

        # ServerName is omitted deliberately: SqlServerDsc defaults it to the local machine, which
        # is where win_dsc already runs. SuppressRestart and RestartTimeout are omitted so the
        # resource performs its own restart, and no credential is emitted. See #64.
        It 'passes only the resource name, the instance and the rule''s two fields' {
            @($dsc.Keys) | Should-BeCollection @('resource_name', 'InstanceName', 'ProtocolName', 'Enabled')
        }

        # The instance is the one thing the rule cannot supply, so it loops a role-scoped list
        # rather than being named per rule.
        It 'loops the role''s instance list, naming each instance bare' {
            $item.Task.loop | Should-Be '{{ stig_sqlserver_2016_instance_instances }}'
            $dsc.InstanceName | Should-Be '{{ item }}'
        }

        It 'names the task for the rule id, its severity and the protocol' {
            $item.Task.name | Should-Be 'V-213961 | MEDIUM | Ensure the NamedPipes protocol is disabled'
        }
    }

    # PowerStig hands the flag over as the text 'True'/'False', and powershell-yaml quotes such a
    # string rather than emitting a YAML boolean - so the generator converts, with an explicit
    # comparison: [bool] 'False' is $true, which would invert the rule silently. See #64 and #69.
    Context 'the enabled flag' {

        It 'converts <Enabled> to the real boolean <Expected>' -ForEach @(
            @{ Enabled = 'False'; Expected = $false }
            @{ Enabled = 'True'; Expected = $true }
        ) {
            $dsc = (Get-SqlProtocolItem -Rule (New-SqlProtocolRule -Enabled $Enabled)).Task.'ansible.windows.win_dsc'

            $dsc.Enabled | Should-HaveType ([bool])
            $dsc.Enabled | Should-Be $Expected
        }

        # The detail reads off the same fields, so a revision that flips either does not leave the
        # role naming a task after what it no longer does.
        It 'names the task for what <Enabled> means' -ForEach @(
            @{ Enabled = 'False'; Expected = 'V-213961 | MEDIUM | Ensure the NamedPipes protocol is disabled' }
            @{ Enabled = 'True'; Expected = 'V-213961 | MEDIUM | Ensure the NamedPipes protocol is enabled' }
        ) {
            (Get-SqlProtocolItem -Rule (New-SqlProtocolRule -Enabled $Enabled)).Task.name | Should-Be $Expected
        }

        It 'names the task for the protocol the rule carries' {
            (Get-SqlProtocolItem -Rule (New-SqlProtocolRule -ProtocolName 'TcpIp')).Task.name |
                Should-Be 'V-213961 | MEDIUM | Ensure the TcpIp protocol is disabled'
        }
    }

    # The generator's RoleVariable is the single source for the reference the task interpolates,
    # the declaration defaults/ carries and the assert guarding it. See #57 and docs/adr/0004.
    Context 'the role variables it declares' {

        It 'declares the same list the tasks loop' {
            $item = Get-SqlProtocolItem -Rule (New-SqlProtocolRule)

            $item.RoleVariable | Should-Be 'instances'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'SqlServer-2016-Instance' |
                Should-ContainCollection @('stig_sqlserver_2016_instance_instances: []')
        }
    }
}
