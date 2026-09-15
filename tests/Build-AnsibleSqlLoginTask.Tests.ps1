#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    # V-213964 verbatim from SqlServer-2016-Instance-3.6.xml; V-271400 in the 2022 STIG carries the
    # same payload and differs only in id and severity.
    function New-SqlLoginRule {
        param (
            $Id = 'V-213964',
            $Severity = 'high',
            $LoginType = 'SqlLogin',
            $LoginPasswordExpirationEnabled = 'True',
            $LoginPasswordPolicyEnforced = 'True',
            $LoginMustChangePassword = 'False'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            Ensure = ''
            Name = ''
            LoginType = $LoginType
            LoginPasswordExpirationEnabled = $LoginPasswordExpirationEnabled
            LoginPasswordPolicyEnforced = $LoginPasswordPolicyEnforced
            LoginMustChangePassword = $LoginMustChangePassword
            OrganizationValueRequired = $true
        }
    }

    # The org node shape PowerStig ships, Name blank: which logins exist is the organization's to
    # answer. -Name fills it in, comma separated the way upstream's composite splits it.
    function Get-SqlLoginOrgSetting {
        param ($Id = 'V-213964', $Name = '')

        New-ContractOrgSetting ('<OrganizationalSetting id="{0}" Ensure="" Name="{1}" />' -f $Id, $Name)
    }

    function Get-SqlLoginItem {
        param ($Rule, $OrganizationalSetting = @{})

        Invoke-Generator -Generator 'Build-AnsibleSqlLoginTask' -Rule $Rule -StigName 'SqlServer-2016-Instance' `
            -OrganizationalSetting $OrganizationalSetting
    }

    # An unanswered organization value wraps the rule in a block with its assert, so the win_dsc
    # task is not always the outer one.
    function Get-SqlLoginTaskBody {
        param ($Task)

        if ($Task.'ansible.windows.win_dsc') { return $Task }

        $Task.block | Where-Object { $_.'ansible.windows.win_dsc' }
    }

    function Export-SqlLoginOrgValues {
        param ($Rules, $OrganizationalSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rules = $Rules; OrganizationalSetting = $OrganizationalSetting
        } {
            param ($Rules, $OrganizationalSetting)

            [pscustomobject] @{ PowerStigRule = 'SqlLoginRule'; StigRule = $Rules } |
                Export-AnsibleOrganizationValue -StigName 'SqlServer-2016-Instance' -OrganizationalSetting $OrganizationalSetting
        }
    }
}

# SqlServerDsc's SqlLogin keys on InstanceName and Name both, so an instance/login pair is a
# resource instance of its own - no union write, and so no shared handler. See #63.
Describe 'Build-AnsibleSqlLoginTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSqlLoginTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'SqlServer-2016-Instance' `
        -Factory { New-SqlLoginRule }

    Context 'the task it builds' {

        BeforeAll {
            $script:item = Get-SqlLoginItem -Rule (New-SqlLoginRule) `
                -OrganizationalSetting (Get-SqlLoginOrgSetting -Name 'sa,svc_app')
            $script:dsc = (Get-SqlLoginTaskBody -Task $item.Task).'ansible.windows.win_dsc'
        }

        It 'uses the SqlLogin DSC resource' {
            $dsc.resource_name | Should-Be 'SqlLogin'
        }

        # Item 2.
        It 'maps <Property> off the rule' -ForEach @(
            @{ Property = 'LoginType'; Expected = 'SqlLogin' }
            @{ Property = 'LoginPasswordPolicyEnforced'; Expected = 'True' }
            @{ Property = 'LoginPasswordExpirationEnabled'; Expected = 'True' }
            @{ Property = 'LoginMustChangePassword'; Expected = 'False' }
        ) {
            $dsc.$Property | Should-Be $Expected
        }

        # Both are Keys of the resource, so every pair needs its own call: one task over the
        # Cartesian product, addressing the pair positionally.
        It 'takes the instance and the login from the pair the loop yields' {
            $dsc.InstanceName | Should-Be '{{ item.0 }}'
            $dsc.Name | Should-Be '{{ item.1 }}'
        }

        It 'loops the instance list against the login list' {
            (Get-SqlLoginTaskBody -Task $item.Task).loop |
                Should-Be '{{ stig_sqlserver_2016_instance_instances | product(stig_sqlserver_2016_instance_213964_logins) | list }}'
        }

        # Upstream never passes Ensure and the rule is about the password policy on logins that
        # already exist, so requiring it would refuse a conversion over a field nothing reads.
        It 'says nothing about Ensure' {
            @($dsc.Keys) | Should-NotContainCollection @('Ensure')
        }

        It 'names the task for <Id>, its severity and the login type' -ForEach @(
            @{ Id = 'V-213964'; Severity = 'high'; Expected = 'V-213964 | HIGH | Ensure the SqlLogin logins enforce the password policy' }
            @{ Id = 'V-271400'; Severity = 'medium'; Expected = 'V-271400 | MEDIUM | Ensure the SqlLogin logins enforce the password policy' }
        ) {
            $rule = New-SqlLoginRule -Id $Id -Severity $Severity

            (Get-SqlLoginItem -Rule $rule -OrganizationalSetting (Get-SqlLoginOrgSetting -Id $Id -Name 'sa')).Task.name |
                Should-Be $Expected
        }
    }

    # Item 6. The org attribute holds a comma-separated list of logins - PowerStig's own composite
    # splits it the same way - and product() needs a sequence, so one login must not unroll to a
    # bare scalar in defaults/.
    Context 'a value the task needs as a list' {

        It 'declares several logins as a flow sequence' {
            $declaration = (Export-SqlLoginOrgValues -Rules @(New-SqlLoginRule) `
                -OrganizationalSetting (Get-SqlLoginOrgSetting -Name 'sa,svc_app')).main_default_org

            $declaration | Should-ContainCollection @('stig_sqlserver_2016_instance_213964_logins: [sa, svc_app]')
        }

        It 'keeps a single login a sequence rather than unrolling it to a scalar' {
            $declaration = (Export-SqlLoginOrgValues -Rules @(New-SqlLoginRule) `
                -OrganizationalSetting (Get-SqlLoginOrgSetting -Name 'sa')).main_default_org

            $declaration | Should-ContainCollection @('stig_sqlserver_2016_instance_213964_logins: [sa]')
        }
    }

    # Item 7. Which logins exist is the organization's answer, so it reaches the task as a variable
    # name inside the product() expression and never as a literal. See docs/adr/0003.
    Context 'a value the organization decides' {

        It 'names the login variable in the loop rather than inlining the logins' {
            $task = (Get-SqlLoginItem -Rule (New-SqlLoginRule) `
                -OrganizationalSetting (Get-SqlLoginOrgSetting -Name 'sa,svc_app')).Task

            $body = Get-SqlLoginTaskBody -Task $task
            $body.loop | Should-BeLikeString '*product(stig_sqlserver_2016_instance_213964_logins)*'
            ($body.'ansible.windows.win_dsc'.Values -join ' ') | Should-NotBeLikeString '*svc_app*'
        }

        # product() is a filter expression, so the bare variable name is what it takes - a {{ }}
        # reference inside it would be nested interpolation.
        It 'names the variable bare, not as a jinja reference' {
            $loop = (Get-SqlLoginTaskBody -Task (Get-SqlLoginItem -Rule (New-SqlLoginRule)).Task).loop

            $loop | Should-NotBeLikeString '*{{ stig_sqlserver_2016_instance_213964_logins }}*'
        }

        It 'guards an unanswered value with an assert' {
            $task = (Get-SqlLoginItem -Rule (New-SqlLoginRule) `
                -OrganizationalSetting (Get-SqlLoginOrgSetting)).Task

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }

    # Item 9. The generator's RoleVariable is the single source for the name the loop reads and the
    # declaration defaults/ carries, so this feeds the generator's own answer to the exporter.
    Context 'the role variables it declares' {

        It 'declares the same instance list the task loops' {
            $item = Get-SqlLoginItem -Rule (New-SqlLoginRule)

            $item.RoleVariable | Should-Be 'instances'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'SqlServer-2016-Instance' |
                Should-ContainCollection @('stig_sqlserver_2016_instance_instances: []')
            (Get-SqlLoginTaskBody -Task $item.Task).loop | Should-BeLikeString '*stig_sqlserver_2016_instance_instances*'
        }
    }
}
