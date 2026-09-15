#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-SqlDatabaseRule {
        param (
            $Id = 'V-213954.a',
            $Name = 'Pubs',
            $Ensure = 'Absent',
            $Severity = 'medium'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            Name = $Name
            Ensure = $Ensure
            OrganizationValueRequired = $false
        }
    }

    # V-213954 verbatim from SqlServer-2016-Instance-3.6: one requirement - remove the sample
    # databases - split into four sub-rules, one per database.
    function Get-SqlDatabaseFixture {
        @(
            New-SqlDatabaseRule -Id 'V-213954.a' -Name 'Pubs'
            New-SqlDatabaseRule -Id 'V-213954.b' -Name 'Northwind'
            New-SqlDatabaseRule -Id 'V-213954.c' -Name 'AdventureWorks'
            New-SqlDatabaseRule -Id 'V-213954.d' -Name 'WorldwideImporters'
        )
    }

    function Get-SqlDatabaseItem {
        param ($Rule)

        Invoke-Generator -Generator 'Build-AnsibleSqlDatabaseTask' -Rule $Rule -StigName 'SqlServer-2016-Instance'
    }

    # A sub-rule is always wrapped in its block, so the win_dsc task is never the outer one.
    function Get-SqlDatabaseDsc {
        param ($Task)

        ($Task.block | Where-Object { $_.'ansible.windows.win_dsc' }).'ansible.windows.win_dsc'
    }
}

# The rule payload is just Name and Ensure; InstanceName is a site fact that comes from the
# role-scoped list all five Sql* generators share, and no organization value, credential or
# handler is involved. See #62.
Describe 'Build-AnsibleSqlDatabaseTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSqlDatabaseTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'SqlServer-2016-Instance' `
        -Factory { New-SqlDatabaseRule }

    Context 'the task it builds' {

        BeforeAll {
            $script:item = Get-SqlDatabaseItem -Rule (New-SqlDatabaseRule)
            $script:dsc = Get-SqlDatabaseDsc -Task $item.Task
        }

        It 'uses the SqlDatabase DSC resource' {
            $dsc.resource_name | Should-Be 'SqlDatabase'
        }

        It 'maps the database name and its ensure off the rule' {
            $dsc.Name | Should-Be 'Pubs'
            $dsc.Ensure | Should-Be 'Absent'
        }

        # ServerName is omitted deliberately: SqlServerDsc defaults it to the local machine, which
        # is where win_dsc already runs, and no credential is emitted either. See #62.
        It 'passes only the resource name, the instance and the rule''s two fields' {
            @($dsc.Keys) | Should-BeCollection @('resource_name', 'InstanceName', 'Name', 'Ensure')
        }

        # The instance is the one thing the rule cannot supply, so it loops a role-scoped list
        # rather than being named per rule.
        It 'loops the role''s instance list, naming each instance bare' {
            $item.Task.block[0].loop | Should-Be '{{ stig_sqlserver_2016_instance_instances }}'
            $dsc.InstanceName | Should-Be '{{ item }}'
        }

        It 'names the task for the sub-rule id, its severity and the database' {
            $item.Task.block[0].name | Should-Be 'V-213954.a | MEDIUM | Ensure Pubs is absent'
        }
    }

    # Group-AnsibleTask keeps the first sub-rule's group name, so a detail naming the database
    # would label the whole block after Pubs. Derived from Ensure alone, it is true of all four.
    Context 'the block the four sub-rules share' {

        It 'names the block from Ensure, so every sub-rule agrees on it' {
            $item = Get-SqlDatabaseFixture | ForEach-Object { Get-SqlDatabaseItem -Rule $_ }

            @($item.Task.name | Sort-Object -Unique) |
                Should-BeCollection @('V-213954 | MEDIUM | Ensure the databases are absent')
        }

        It 'collapses the four sub-rules into one block' {
            $item = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rules = Get-SqlDatabaseFixture } {
                param ($Rules)

                $Rules | ConvertTo-AnsibleTask -RuleType 'SqlDatabase' -StigName 'SqlServer-2016-Instance'
            }

            @($item).Count | Should-Be 1
            @($item.Task.block).Count | Should-Be 4
            $item.Task.when | Should-Be 'stig_sqlserver_2016_instance_213954_when'
        }
    }

    # The generator's RoleVariable is the single source for the reference the task interpolates,
    # the declaration defaults/ carries and the assert guarding it. See #57 and docs/adr/0004.
    Context 'the role variables it declares' {

        It 'declares the same list the tasks loop' {
            $item = Get-SqlDatabaseItem -Rule (New-SqlDatabaseRule)

            $item.RoleVariable | Should-Be 'instances'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'SqlServer-2016-Instance' |
                Should-ContainCollection @('stig_sqlserver_2016_instance_instances: []')
        }
    }
}
