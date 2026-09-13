#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Eight rule types had no fixture carrying them, so no conversion ever ran them end to end. Each
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
            # SslSettings is the one rule type whose work lands outside tasks/, so this reads the
            # handler files too.
            Handlers = Get-Content (Join-Path $role.HandlerPath 'generated.yml') -Raw
            HandlerMain = Get-Content (Join-Path $role.HandlerPath 'main.yml') -Raw
        }
    }
}

Describe 'New-AnsiblePlaybook for the rule types no other fixture carried' {

    BeforeAll {
        $script:dc = Get-RoleContent -StigName 'WindowsServer-2022-DC' -RoleName 'dc_role'
        $script:iis = Get-RoleContent -StigName 'IISServer-10.0' -RoleName 'iis_cover_role'
        $script:site = Get-RoleContent -StigName 'IISSite-10.0' -RoleName 'iis_site_cover_role'
    }

    It 'converts an <RuleType> rule into <Module>' -ForEach @(
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'dc' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'dc' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'dc' }
        @{ RuleType = 'Service'; Module = 'ansible.windows.win_service_info'; Role = 'dc' }
        @{ RuleType = 'MimeType'; Module = 'IISMimeTypeMapping'; Role = 'iis' }
        @{ RuleType = 'WebConfigurationProperty'; Module = 'WebConfigProperty'; Role = 'iis' }
        @{ RuleType = 'WebAppPool'; Module = 'WebAppPool'; Role = 'site' }
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
        @{ RuleType = 'SslSettings'; Toggle = 'stig_iissite_10_0_218737_when'; Role = 'site' }
        @{ RuleType = 'WebAppPool'; Toggle = 'stig_iissite_10_0_218777_when'; Role = 'site' }
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

    # The one rule type whose work does not land in tasks/ at all: each rule only contributes its
    # flags, and nothing is written until the handler runs. A conversion is the only thing that
    # shows the contribution and the write meeting - the generator's own test sees both halves
    # separately, and neither proves the handler reached handlers/ or that anything imports it.
    Context 'SslSettings, whose write happens in a handler' {

        It 'contributes both rules'' flags to one list, across two severities' {
            $site.Tasks | Should-MatchString "\+ \['Ssl128'\]"
            $site.Tasks | Should-MatchString "\+ \['Ssl', 'SslNegotiateCert', 'SslRequireCert'\]"
        }

        It 'writes the one handler both rules notify' {
            $site.Tasks | Should-BeLikeString '*notify: apply_ssl_settings*'
            $site.Handlers | Should-BeLikeString '*name: apply_ssl_settings*'
            $site.Handlers | Should-BeLikeString '*resource_name: SslSettings*'
        }

        # Two rules, one handler: the exporter dedupes by name, or the play fails on a duplicate.
        It 'writes it once, though both rules produced it' {
            ([regex]::Matches($site.Handlers, 'name: apply_ssl_settings')).Count | Should-Be 1
        }

        It 'imports the generated handlers from the scaffolded handlers/main.yml' {
            $site.HandlerMain | Should-BeLikeString '*generated.yml*'
        }

        It 'declares the website list the handler loops over' {
            $site.Handlers | Should-BeLikeString '*{{ stig_iissite_10_0_websites }}*'
            $site.Defaults | Should-MatchString 'stig_iissite_10_0_websites: \[\]'
        }
    }

    Context 'WebAppPool, whose values are PowerShell literals upstream' {

        It 'declares the app pool list every rule loops over' {
            $site.Tasks | Should-BeLikeString '*{{ stig_iissite_10_0_webapppools }}*'
            $site.Defaults | Should-MatchString 'stig_iissite_10_0_webapppools: \[\]'
        }

        # PowerStig quotes this one because xWebAppPool interpolates it into a scriptblock it
        # builds as a string; the role has to strip those quotes and put YAML's own back, or
        # ansible's YAML 1.1 reads 00:05:00 as the sexagesimal 300.
        It 'unquotes the organisation''s timespan and requotes it for YAML' {
            $site.Defaults | Should-BeLikeString "*stig_iissite_10_0_218778_rapidfailprotectioninterval: '00:05:00'*"
            $site.Tasks | Should-BeLikeString '*{{ stig_iissite_10_0_218778_rapidfailprotectioninterval }}*'
        }

        It 'translates the rule''s own PowerShell boolean' {
            $site.Tasks | Should-BeLikeString '*rapidFailProtection: true*'
        }
    }

    # The site branch of the two generators that have one. The server fixture takes the other.
    Context 'the IIS rule types a site STIG scopes to a website' {

        It 'scopes <RuleType> to a site rather than the machine' -ForEach @(
            @{ RuleType = 'MimeType'; Reference = 'IIS:\Sites\{{ stig_iissite_10_0_218785_website }}' }
            @{ RuleType = 'WebConfigurationProperty'; Reference = 'IIS:\Sites\{{ stig_iissite_10_0_218786_website }}' }
        ) {
            $site.Tasks | Should-BeLikeString "*$Reference*"
        }
    }
}
