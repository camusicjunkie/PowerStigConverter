#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Six rule types had no fixture carrying them, so no conversion ever ran them end to end. Each
    had a direct test, but a direct test cannot catch a rule type that never reaches the role at
    all - a missing adapter, a dispatcher that skips it, an exporter that drops it.

    This runs the whole conversion over the fixtures that now carry them and checks each one
    arrives. It asserts that a rule reached the role, not how its task is built; that is the
    direct test's job.
#>

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'

    function Get-RoleContent {
        param ($StigName, $RoleName)

        $role = New-AnsiblePlaybook -StigName $StigName -Path $fixtureRoot `
            -OutputPath (Join-Path $TestDrive $RoleName) -RoleName $RoleName `
            -WarningAction SilentlyContinue 6>$null

        @{
            Tasks = (Get-ChildItem $role.TaskPath -Filter 'cat*.yml' | Get-Content -Raw) -join "`n"
            Defaults = (Get-ChildItem $role.DefaultPath -Filter '*.yml' | Get-Content -Raw) -join "`n"
        }
    }
}

Describe 'New-AnsiblePlaybook for the rule types no other fixture carried' {

    BeforeAll {
        $script:dc = Get-RoleContent -StigName 'WindowsServer-2022-DC' -RoleName 'dc_role'
        $script:iis = Get-RoleContent -StigName 'IISServer-10.0' -RoleName 'iis_cover_role'
    }

    It 'converts an <RuleType> rule into <Module>' -ForEach @(
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'dc' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'dc' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'dc' }
        @{ RuleType = 'Service'; Module = 'ansible.windows.win_service_info'; Role = 'dc' }
        @{ RuleType = 'MimeType'; Module = 'IISMimeTypeMapping'; Role = 'iis' }
        @{ RuleType = 'WebConfigurationProperty'; Module = 'WebConfigProperty'; Role = 'iis' }
    ) {
        (Get-Variable -Name $Role -ValueOnly).Tasks | Should-BeLikeString "*$Module*"
    }

    # A rule that reaches the role but has no toggle cannot be switched off by an operator.
    It 'declares a toggle for <RuleType>' -ForEach @(
        @{ RuleType = 'AuditSetting'; Toggle = 'stig_server_2022_400_when'; Role = 'dc' }
        @{ RuleType = 'Permission'; Toggle = 'stig_server_2022_401_when'; Role = 'dc' }
        @{ RuleType = 'RootCertificate'; Toggle = 'stig_server_2022_402_when'; Role = 'dc' }
        @{ RuleType = 'Service'; Toggle = 'stig_server_2022_403_when'; Role = 'dc' }
        @{ RuleType = 'MimeType'; Toggle = 'stig_iisserver_10_0_301_when'; Role = 'iis' }
        @{ RuleType = 'WebConfigurationProperty'; Toggle = 'stig_iisserver_10_0_302_when'; Role = 'iis' }
    ) {
        (Get-Variable -Name $Role -ValueOnly).Defaults | Should-BeLikeString "*$Toggle*"
    }

    # Both of these leave their values to the organisation, so the task must interpolate a
    # variable defaults/ declares rather than inlining anything. See docs/adr/0003.
    Context 'the two rule types whose values the organisation decides' {

        It 'declares and references the certificate store and its location' {
            $dc.Defaults | Should-BeLikeString '*stig_server_2022_402_store_name: Root*'
            $dc.Defaults | Should-BeLikeString '*stig_server_2022_402_store_location: LocalMachine*'
            $dc.Tasks | Should-BeLikeString '*{{ stig_server_2022_402_store_name }}*'
        }

        It 'declares and references the service name and its startup type' {
            $dc.Defaults | Should-BeLikeString '*stig_server_2022_403_servicename: WinDefend*'
            $dc.Defaults | Should-BeLikeString '*stig_server_2022_403_startuptype: Automatic*'
            $dc.Tasks | Should-BeLikeString '*{{ stig_server_2022_403_servicename }}*'
        }

        # Every value is answered in the fixture's org settings, so nothing should be guarded.
        It 'guards nothing, because the org settings file answers every value' {
            $dc.Tasks | Should-NotBeLikeString '*Assert the organization values*'
        }
    }

    Context 'a rule that becomes several tasks' {

        It 'gives each access control entry its own task in one block' {
            $dc.Tasks | Should-BeLikeString '*Administrators*'
            $dc.Tasks | Should-BeLikeString '*SYSTEM*'
        }
    }
}
