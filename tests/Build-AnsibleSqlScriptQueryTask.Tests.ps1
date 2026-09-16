#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    # V-214029 verbatim from SqlServer-2016-Instance-3.6.xml - the one rule in either STIG whose
    # value the organization decides, and the shortest real script triad of the lot.
    function New-SqlScriptQueryRule {
        param (
            $Id = 'V-214029',
            $Severity = 'medium',
            $Variable = 'saAccountName={0}',
            $OrganizationValueRequired = $true,
            $SetScript = 'alter login sa with name = [$(saAccountName)]'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            GetScript = "SELECT name FROM sys.server_principals WHERE TYPE = 'S' and name not like '%##%'"
            TestScript = "SELECT name FROM sys.server_principals WHERE TYPE = 'S' and name = 'sa'"
            SetScript = $SetScript
            Variable = $Variable
            VariableValue = ''
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    # V-274445 from SqlServer-2022-Instance-1.4.xml: the same requirement as V-214029, shipped with
    # no Variable, no organization value and no org.default.xml entry - so the $(saAccountName) its
    # SetScript uses is bound by nothing. An upstream data defect; see #65.
    function New-SqlScriptQueryDefectRule {
        New-SqlScriptQueryRule -Id 'V-274445' -Variable '' -OrganizationValueRequired $false
    }

    # The org node shape PowerStig ships, VariableValue blank: what the [sa] account should be
    # renamed to is the organization's to answer.
    function Get-SqlScriptQueryOrgSetting {
        param ($Id = 'V-214029', $VariableValue = '')

        New-ContractOrgSetting ('<OrganizationalSetting id="{0}" VariableValue="{1}" />' -f $Id, $VariableValue)
    }

    function Get-SqlScriptQueryItem {
        param ($Rule, $OrganizationalSetting = @{})

        Invoke-Generator -Generator 'Build-AnsibleSqlScriptQueryTask' -Rule $Rule -StigName 'SqlServer-2016-Instance' `
            -OrganizationalSetting $OrganizationalSetting
    }

    # An unanswered organization value wraps the rule in a block with its assert, so the win_dsc
    # task is not always the outer one.
    function Get-SqlScriptQueryTaskBody {
        param ($Task)

        if ($Task.'ansible.windows.win_dsc') { return $Task }

        $Task.block | Where-Object { $_.'ansible.windows.win_dsc' }
    }

    # The warning is written from inside the module, so it is read off the warning stream rather
    # than through a mock.
    function Get-SqlScriptQueryWarning {
        param ($Rule)

        @(Get-SqlScriptQueryItem -Rule $Rule -OrganizationalSetting (Get-SqlScriptQueryOrgSetting -VariableValue 'sqladmin') 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    }
}

# One task per rule carrying the rule's own Get/Test/Set triad verbatim. No handler and no union:
# the eight rules sharing a SetScript share it byte for byte, so whichever runs first satisfies
# them all. See #65.
Describe 'Build-AnsibleSqlScriptQueryTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSqlScriptQueryTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'SqlServer-2016-Instance' `
        -Factory { New-SqlScriptQueryRule }

    Context 'the task it builds' {

        BeforeAll {
            $script:item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryRule) `
                -OrganizationalSetting (Get-SqlScriptQueryOrgSetting -VariableValue 'sqladmin')
            $script:dsc = (Get-SqlScriptQueryTaskBody -Task $item.Task).'ansible.windows.win_dsc'
        }

        It 'uses the SqlScriptQuery DSC resource' {
            $dsc.resource_name | Should-Be 'SqlScriptQuery'
        }

        # Item 2. The rule states all three; the converter authors no T-SQL of its own.
        It 'maps <Property> off the rule''s <Field>' -ForEach @(
            @{ Property = 'GetQuery'; Field = 'GetScript'; Expected = "SELECT name FROM sys.server_principals WHERE TYPE = 'S' and name not like '%##%'" }
            @{ Property = 'TestQuery'; Field = 'TestScript'; Expected = "SELECT name FROM sys.server_principals WHERE TYPE = 'S' and name = 'sa'" }
            @{ Property = 'SetQuery'; Field = 'SetScript'; Expected = 'alter login sa with name = [$(saAccountName)]' }
        ) {
            $dsc.$Property | Should-Be $Expected
        }

        # A Key on SqlServerDsc 17.x and absent before it, which is what puts generated SQL roles
        # on a 17.x+ floor. Upstream never uses the value, so the rule id is the free choice.
        It 'identifies the resource instance by the rule id' {
            $dsc.Id | Should-Be 'V-214029'
        }

        # ServerName, Credential, DisableVariables, QueryTimeout and Encrypt are all omitted
        # deliberately - each is a fact about the target, not something the rule states. Pinning
        # the key set asserts the omissions rather than leaving them merely absent. See #65.
        It 'passes only the resource name, the id, the instance, the three queries and the variable' {
            @($dsc.Keys) | Should-BeCollection @('resource_name', 'Id', 'InstanceName', 'GetQuery', 'TestQuery', 'SetQuery', 'Variable')
        }

        # The instance is the one thing the rule cannot supply, so it loops a role-scoped list
        # rather than being named per rule.
        It 'loops the role''s instance list, naming each instance bare' {
            (Get-SqlScriptQueryTaskBody -Task $item.Task).loop | Should-Be '{{ stig_sqlserver_2016_instance_instances }}'
            $dsc.InstanceName | Should-Be '{{ item }}'
        }

        # Nothing in the rule separates one script requirement from another - eight of 2016's ten
        # are indistinguishable by SetScript - so the detail says so plainly and the id and
        # severity do the indexing.
        It 'names the task for <Id>, its severity and a fixed detail' -ForEach @(
            @{ Id = 'V-214029'; Severity = 'medium'; Expected = 'V-214029 | MEDIUM | Ensure the SQL script requirement is met' }
            @{ Id = 'V-213939'; Severity = 'high'; Expected = 'V-213939 | HIGH | Ensure the SQL script requirement is met' }
        ) {
            $rule = New-SqlScriptQueryRule -Id $Id -Severity $Severity

            (Get-SqlScriptQueryItem -Rule $rule `
                -OrganizationalSetting (Get-SqlScriptQueryOrgSetting -Id $Id -VariableValue 'sqladmin')).Task.name |
                Should-Be $Expected
        }
    }

    # Invoke-SqlCmd substitutes $(name) before the script reaches SQL Server, so a script with a
    # blank in it needs the rule to say what fills the blank. Most rules have neither.
    Context 'the scripting variables the script binds' {

        It 'substitutes the value into the rule''s own template' {
            $item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryRule) `
                -OrganizationalSetting (Get-SqlScriptQueryOrgSetting -VariableValue 'sqladmin')

            $dsc = (Get-SqlScriptQueryTaskBody -Task $item.Task).'ansible.windows.win_dsc'
            @($dsc.Variable) | Should-BeCollection @('saAccountName={{ stig_sqlserver_2016_instance_214029_variablevalue }}')
        }

        # A String[] property, so one binding must not unroll to a bare scalar.
        It 'keeps a single binding a sequence' {
            $item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryRule) `
                -OrganizationalSetting (Get-SqlScriptQueryOrgSetting -VariableValue 'sqladmin')

            $dsc = (Get-SqlScriptQueryTaskBody -Task $item.Task).'ansible.windows.win_dsc'
            $dsc.Variable -is [array] | Should-BeTrue
        }

        # PowerStig's own composite omits the property rather than passing an empty one.
        It 'says nothing about Variable for a rule that declares none' {
            $item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryDefectRule)

            $dsc = (Get-SqlScriptQueryTaskBody -Task $item.Task).'ansible.windows.win_dsc'
            @($dsc.Keys) | Should-BeCollection @('resource_name', 'Id', 'InstanceName', 'GetQuery', 'TestQuery', 'SetQuery')
        }
    }

    # V-274445's script uses $(saAccountName) and the rule binds nothing to it, so the task fails
    # at run time - and only on the instances that actually needed fixing. Converted literally,
    # because repairing upstream's data is not this module's job, but not silently. See #65.
    Context 'a script variable the rule leaves unbound' {

        It 'warns, naming the rule and the variable' {
            $warning = Get-SqlScriptQueryWarning -Rule (New-SqlScriptQueryDefectRule)

            @($warning).Count | Should-Be 1
            $warning[0].Message | Should-BeLikeString '*V-274445*'
            $warning[0].Message | Should-BeLikeString '*saAccountName*'
        }

        It 'still emits the task rather than dropping the rule' {
            $item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryDefectRule)

            (Get-SqlScriptQueryTaskBody -Task $item.Task).'ansible.windows.win_dsc'.SetQuery |
                Should-Be 'alter login sa with name = [$(saAccountName)]'
        }

        It 'stays quiet when the rule binds the variable its script uses' {
            Get-SqlScriptQueryWarning -Rule (New-SqlScriptQueryRule) | Should-BeCollection @()
        }

        It 'stays quiet for a script with no scripting variable in it' {
            $rule = New-SqlScriptQueryRule -Variable '' -OrganizationValueRequired $false `
                -SetScript 'ALTER SERVER AUDIT STIG_AUDIT WITH (STATE = ON)'

            Get-SqlScriptQueryWarning -Rule $rule | Should-BeCollection @()
        }
    }

    # Item 7. What the [sa] account is renamed to is the organization's answer, so it reaches the
    # task as a variable reference inside the binding and never as a literal. See docs/adr/0003.
    Context 'a value the organization decides' {

        It 'references the variable rather than inlining the answer' {
            $item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryRule) `
                -OrganizationalSetting (Get-SqlScriptQueryOrgSetting -VariableValue 'sqladmin')

            $dsc = (Get-SqlScriptQueryTaskBody -Task $item.Task).'ansible.windows.win_dsc'
            @($dsc.Variable) | Should-BeCollection @('saAccountName={{ stig_sqlserver_2016_instance_214029_variablevalue }}')
            ($dsc.Values | ForEach-Object { $_ }) -join ' ' | Should-NotBeLikeString '*sqladmin*'
        }

        It 'guards an unanswered value with an assert' {
            $task = (Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryRule) `
                -OrganizationalSetting (Get-SqlScriptQueryOrgSetting)).Task

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }

    # Item 9. The generator's RoleVariable is the single source for the reference its task
    # interpolates and the declaration defaults/ carries. See #57 and docs/adr/0004.
    Context 'the role variables it declares' {

        It 'declares the same instance list the task loops' {
            $item = Get-SqlScriptQueryItem -Rule (New-SqlScriptQueryRule)

            $item.RoleVariable | Should-Be 'instances'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'SqlServer-2016-Instance' |
                Should-ContainCollection @('stig_sqlserver_2016_instance_instances: []')
            (Get-SqlScriptQueryTaskBody -Task $item.Task).loop | Should-BeLikeString '*stig_sqlserver_2016_instance_instances*'
        }
    }
}
