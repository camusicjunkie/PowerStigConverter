#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-WebAppPoolRule {
        param (
            $Id = 'V-218777',
            $Key = 'rapidFailProtection',
            $Value = '$true',
            $OrganizationValueRequired = $false,
            $Severity = 'medium'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            Key = $Key
            Value = $Value
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    # The five WebAppPool rules IISSite-10.0 actually carries: four the organization answers and
    # V-218777, which carries its own literal. Keyed by id so a case names the one it is about.
    function Get-WebAppPoolFixture {
        @{
            'V-218762' = New-WebAppPoolRule -Id 'V-218762' -Key 'idleTimeout' -Value '' -OrganizationValueRequired $true
            'V-218772' = New-WebAppPoolRule -Id 'V-218772' -Key 'restartRequestsLimit' -Value '' -OrganizationValueRequired $true
            'V-218775' = New-WebAppPoolRule -Id 'V-218775' -Key 'logEventOnRecycle' -Value '' -OrganizationValueRequired $true
            'V-218777' = New-WebAppPoolRule
            'V-218778' = New-WebAppPoolRule -Id 'V-218778' -Key 'rapidFailProtectionInterval' -Value '' -OrganizationValueRequired $true
        }
    }

    # The org defaults verbatim from IISSite-10.0-2.15.org.default.xml, quotes and all: V-218762 is
    # left blank for the organization, and two of the answered ones are PowerShell literals.
    function Get-WebAppPoolOrgSetting {
        New-ContractOrgSetting @'
<OrganizationalSetting id="V-218762" Value="" />
<OrganizationalSetting id="V-218772" Value="35000" />
<OrganizationalSetting id="V-218775" Value="'Time,Requests,Schedule,Memory,IsapiUnhealthy,OnDemand,ConfigChange,PrivateMemory'" />
<OrganizationalSetting id="V-218778" Value="'00:05:00'" />
'@
    }

    function Get-WebAppPoolItem {
        param ($Rule, $OrganizationalSetting = @{})

        Invoke-Generator -Generator 'Build-AnsibleWebAppPoolTask' -Rule $Rule -StigName 'IISSite-10.0' `
            -OrganizationalSetting $OrganizationalSetting
    }

    # An unanswered organization value wraps the rule in a block with its assert, so the win_dsc
    # task is not always the outer one.
    function Get-WebAppPoolDsc {
        param ($Task)

        if ($Task.'ansible.windows.win_dsc') { return $Task.'ansible.windows.win_dsc' }

        ($Task.block | Where-Object { $_.'ansible.windows.win_dsc' }).'ansible.windows.win_dsc'
    }

    function Export-WebAppPoolOrgValues {
        param ($Rules, $OrganizationalSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rules = $Rules; OrganizationalSetting = $OrganizationalSetting
        } {
            param ($Rules, $OrganizationalSetting)

            [pscustomobject] @{ PowerStigRule = 'WebAppPoolRule'; StigRule = $Rules } |
                Export-AnsibleOrganizationValue -StigName 'IISSite-10.0' -OrganizationalSetting $OrganizationalSetting
        }
    }
}

# Each rule sets a different property of the pool and the DSC resource writes only what it is
# passed, so these stay one task per rule rather than collapsing onto a shared handler the way
# SslSettings has to. See #53.
Describe 'Build-AnsibleWebAppPoolTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleWebAppPoolTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'IISSite-10.0' `
        -Factory { New-WebAppPoolRule }

    Context 'the task it builds' {

        BeforeAll {
            $script:dsc = (Get-WebAppPoolItem -Rule (New-WebAppPoolRule)).Task.'ansible.windows.win_dsc'
        }

        It 'uses the WebAppPool DSC resource' {
            $dsc.resource_name | Should-Be 'WebAppPool'
        }

        # The STIG says "perform the following for each Application Pool", so the pools come from
        # a role-scoped list rather than one variable per rule.
        It 'loops the role''s app pool list, naming each pool bare' {
            (Get-WebAppPoolItem -Rule (New-WebAppPoolRule)).Task.loop | Should-Be '{{ stig_iissite_10_0_webapppools }}'
            $dsc.Name | Should-Be '{{ item }}'
        }

        It 'maps the rule''s Key onto the DSC property it names' -ForEach @(
            @{ Id = 'V-218762'; Key = 'idleTimeout' }
            @{ Id = 'V-218772'; Key = 'restartRequestsLimit' }
            @{ Id = 'V-218775'; Key = 'logEventOnRecycle' }
            @{ Id = 'V-218777'; Key = 'rapidFailProtection' }
            @{ Id = 'V-218778'; Key = 'rapidFailProtectionInterval' }
        ) {
            $rule = (Get-WebAppPoolFixture)[$Id]

            $task = (Get-WebAppPoolItem -Rule $rule -OrganizationalSetting (Get-WebAppPoolOrgSetting)).Task

            @((Get-WebAppPoolDsc -Task $task).Keys) | Should-ContainCollection @($Key)
        }

        It 'names the task for the rule id, its severity and the property' {
            (Get-WebAppPoolItem -Rule (New-WebAppPoolRule)).Task.name |
                Should-Be 'V-218777 | MEDIUM | Ensure rapidFailProtection'
        }
    }

    # V-218777 is the one rule carrying its own value, and PowerStig writes it as the PowerShell
    # source its scriptblock builder needs. rapidFailProtection is a [Boolean] DSC parameter, so
    # the literal has to become a real boolean or win_dsc is handed the string '$true'.
    Context 'the rule''s own literal value' {

        It 'translates the literal $true to a boolean' {
            $value = (Get-WebAppPoolItem -Rule (New-WebAppPoolRule)).Task.'ansible.windows.win_dsc'.rapidFailProtection

            $value | Should-BeTrue
            $value.GetType().Name | Should-Be 'Boolean'
        }

        It 'translates the literal $false to a boolean' {
            $rule = New-WebAppPoolRule -Value '$false'

            $value = (Get-WebAppPoolItem -Rule $rule).Task.'ansible.windows.win_dsc'.rapidFailProtection

            $value | Should-BeFalse
            $value.GetType().Name | Should-Be 'Boolean'
        }
    }

    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a value' {
            $rule = (Get-WebAppPoolFixture)['V-218772']

            $dsc = (Get-WebAppPoolItem -Rule $rule -OrganizationalSetting (Get-WebAppPoolOrgSetting)).Task.'ansible.windows.win_dsc'

            $dsc.restartRequestsLimit | Should-Be '{{ stig_iissite_10_0_218772_restartrequestslimit }}'
        }

        # All five rules read the same org node attribute, so naming the variable after it would
        # leave the rule id as the only thing telling them apart.
        It 'names the variable after the property, not the attribute they all share' {
            $declaration = (Export-WebAppPoolOrgValues -Rules @((Get-WebAppPoolFixture).Values) `
                -OrganizationalSetting (Get-WebAppPoolOrgSetting)).main_default_org

            $declaration | Should-ContainCollection @('stig_iissite_10_0_218762_idletimeout: ')
            $declaration | Should-ContainCollection @('stig_iissite_10_0_218775_logeventonrecycle: Time,Requests,Schedule,Memory,IsapiUnhealthy,OnDemand,ConfigChange,PrivateMemory')
        }

        It 'guards an unanswered value with an assert' {
            $rule = (Get-WebAppPoolFixture)['V-218762']

            $task = (Get-WebAppPoolItem -Rule $rule -OrganizationalSetting (Get-WebAppPoolOrgSetting)).Task

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }

    # Unquote's reason for existing: without it the declaration reads "'00:05:00'" and DSC's
    # [TimeSpan]::Parse throws on the inner quotes.
    Context 'an organization default quoted as a PowerShell literal' {

        It 'declares the timespan unquoted, so yaml keeps it a string rather than a sexagesimal' {
            $declaration = (Export-WebAppPoolOrgValues -Rules @((Get-WebAppPoolFixture)['V-218778']) `
                -OrganizationalSetting (Get-WebAppPoolOrgSetting)).main_default_org

            $declaration | Should-ContainCollection @("stig_iissite_10_0_218778_rapidfailprotectioninterval: '00:05:00'")
        }

        It 'leaves an unquoted default alone' {
            $declaration = (Export-WebAppPoolOrgValues -Rules @((Get-WebAppPoolFixture)['V-218772']) `
                -OrganizationalSetting (Get-WebAppPoolOrgSetting)).main_default_org

            $declaration | Should-ContainCollection @('stig_iissite_10_0_218772_restartrequestslimit: 35000')
        }
    }

    # The generator's RoleVariable is the single source for the reference above, the declaration
    # defaults/ carries and the assert guarding it, so this pins the pair by feeding the
    # generator's own answer to the exporter. See #57 and docs/adr/0004.
    Context 'the role variables it declares' {

        It 'declares the same list the tasks loop' {
            $item = Get-WebAppPoolItem -Rule (New-WebAppPoolRule)

            $item.RoleVariable | Should-Be 'webapppools'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'IISSite-10.0' |
                Should-ContainCollection @('stig_iissite_10_0_webapppools: []')
        }
    }
}
