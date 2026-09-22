#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Thirteen rule types had no fixture carrying them, so no conversion ever ran them end to end.
    Each had a direct test, but a direct test cannot catch a rule type that never reaches the role
    at all - a missing adapter, a dispatcher that skips it, an exporter that drops it.

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
            -WarningAction SilentlyContinue -WarningVariable warning 6>$null

        $taskFile = @{}
        foreach ($file in Get-ChildItem $role.TaskPath -Filter 'cat*.yml') {
            $taskFile[$file.BaseName] = Get-Content $file.FullName -Raw
        }

        @{
            Tasks = (Get-ChildItem $role.TaskPath -Filter 'cat*.yml' | Get-Content -Raw) -join "`n"
            # Kept apart as well as joined: the role-variable assert is repeated per severity file,
            # so a case has to be able to look inside one rather than at all three at once.
            TaskFile = $taskFile
            # The hand-editable scaffold file itself, for the two cases only a real conversion can
            # show: which OS assertion Plaster picked, and that no Server Core fact was set.
            TaskMain = Get-Content (Join-Path $role.TaskPath 'main.yml') -Raw
            Defaults = (Get-ChildItem $role.DefaultPath -Filter '*.yml' | Get-Content -Raw) -join "`n"
            # SslSettings is the one rule type whose work lands outside tasks/, so this reads the
            # handler files too.
            Handlers = Get-Content (Join-Path $role.HandlerPath 'generated.yml') -Raw
            HandlerMain = Get-Content (Join-Path $role.HandlerPath 'main.yml') -Raw
            # A warning is the only thing one rule type produces that no file records, so a case
            # cannot read it off the role. See the V-274445 case below.
            Warnings = @($warning | ForEach-Object { $_.ToString() })
        }
    }
}

Describe 'New-AnsiblePlaybook for the rule types no other fixture carried' {

    BeforeAll {
        $script:dc = Get-RoleContent -StigName 'WindowsServer-2022-DC' -RoleName 'dc_role'
        $script:iis = Get-RoleContent -StigName 'IISServer-10.0' -RoleName 'iis_cover_role'
        $script:site = Get-RoleContent -StigName 'IISSite-10.0' -RoleName 'iis_site_cover_role'
        # Two SQL fixtures because the STIGs differ: 2016 is the only one carrying SqlDatabase,
        # SqlProtocol and SecurityOption, and 2022 is the only one whose Registry rules leave
        # their value to the organisation.
        $script:sql2016 = Get-RoleContent -StigName 'SqlServer-2016-Instance' -RoleName 'sql_2016_cover_role'
        $script:sql2022 = Get-RoleContent -StigName 'SqlServer-2022-Instance' -RoleName 'sql_2022_cover_role'
        # Three Linux fixtures: RHEL-9 carries the organization-value and unparsed nxFileLine
        # rules plus V-257779's banner; OracleLinux-8 is the only in-scope product carrying
        # nxService; OracleLinux-9 adds the 3 unparsed Permission rules. See #86.
        $script:rhel = Get-RoleContent -StigName 'RHEL-9' -RoleName 'rhel_cover_role'
        $script:ol8 = Get-RoleContent -StigName 'OracleLinux-8' -RoleName 'ol8_cover_role'
        $script:ol9 = Get-RoleContent -StigName 'OracleLinux-9' -RoleName 'ol9_cover_role'
        # WindowsServer-2025-DC/-MS-1.1: real trimmed data, surveyed against 2022's shape for
        # #95's map. Both fixtures carry a real rule of every one of the eleven rule types the
        # product has.
        $script:dc2025 = Get-RoleContent -StigName 'WindowsServer-2025-DC' -RoleName 'dc2025_role'
        $script:ms2025 = Get-RoleContent -StigName 'WindowsServer-2025-MS' -RoleName 'ms2025_role'
        # WindowsClient-10-3.6/WindowsClient-11-2.7: real trimmed data, surveyed against the
        # WindowsServer generators' shape for #99's map (#98). Both fixtures carry a real rule of
        # every one of the twelve rule types the product has; the survey found two real generator
        # defects rather than merely-unproven shapes, split out as #100 and #101 and now fixed.
        $script:client10 = Get-RoleContent -StigName 'WindowsClient-10' -RoleName 'client10_role'
        $script:client11 = Get-RoleContent -StigName 'WindowsClient-11' -RoleName 'client11_role'
        # Google-Chrome-2.11: real trimmed data, surveyed for #103's map. Chrome carries only the
        # two rule types every prior Windows map has already proven; this fixture is what shows
        # dispatch actually reaches both from Chrome's own real data.
        $script:chrome = Get-RoleContent -StigName 'Google-Chrome' -RoleName 'chrome_role'
        # MS-Edge-2.5: real trimmed data, surveyed for #103's map (#105). Edge carries a third
        # rule type, Document, alongside the Registry and Manual shapes Chrome already proved.
        $script:edge = Get-RoleContent -StigName 'MS-Edge' -RoleName 'edge_role'
    }

    It 'converts an <RuleType> rule into <Module>' -ForEach @(
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'dc' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'dc' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'dc' }
        @{ RuleType = 'Service'; Module = 'ansible.windows.win_service_info'; Role = 'dc' }
        @{ RuleType = 'MimeType'; Module = 'IISMimeTypeMapping'; Role = 'iis' }
        @{ RuleType = 'WebConfigurationProperty'; Module = 'WebConfigProperty'; Role = 'iis' }
        @{ RuleType = 'WebAppPool'; Module = 'WebAppPool'; Role = 'site' }
        @{ RuleType = 'SqlDatabase'; Module = 'resource_name: SqlDatabase'; Role = 'sql2016' }
        @{ RuleType = 'SqlProtocol'; Module = 'resource_name: SqlProtocol'; Role = 'sql2016' }
        @{ RuleType = 'SqlLogin'; Module = 'resource_name: SqlLogin'; Role = 'sql2016' }
        @{ RuleType = 'SqlScriptQuery'; Module = 'resource_name: SqlScriptQuery'; Role = 'sql2016' }
        @{ RuleType = 'SqlServerConfiguration'; Module = 'resource_name: SqlConfiguration'; Role = 'sql2016' }
        # The four 2022 carries, so a rule type reaching one role but not the other is visible.
        @{ RuleType = 'SqlLogin'; Module = 'resource_name: SqlLogin'; Role = 'sql2022' }
        @{ RuleType = 'SqlScriptQuery'; Module = 'resource_name: SqlScriptQuery'; Role = 'sql2022' }
        @{ RuleType = 'SqlServerConfiguration'; Module = 'resource_name: SqlConfiguration'; Role = 'sql2022' }
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'sql2022' }
        # WindowsServer-2025-DC/-MS: every one of the eleven rule types the product carries,
        # dispatched from real data. See #95 and #96.
        @{ RuleType = 'AccountPolicy'; Module = 'community.windows.win_security_policy'; Role = 'dc2025' }
        @{ RuleType = 'AuditPolicy'; Module = 'community.windows.win_audit_policy_system'; Role = 'dc2025' }
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'dc2025' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'dc2025' }
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'dc2025' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'dc2025' }
        @{ RuleType = 'SecurityOption'; Module = 'community.windows.win_security_policy'; Role = 'dc2025' }
        @{ RuleType = 'UserRight'; Module = 'ansible.windows.win_user_right'; Role = 'dc2025' }
        @{ RuleType = 'WindowsFeature'; Module = 'ansible.windows.win_feature'; Role = 'dc2025' }
        @{ RuleType = 'AccountPolicy'; Module = 'community.windows.win_security_policy'; Role = 'ms2025' }
        @{ RuleType = 'AuditPolicy'; Module = 'community.windows.win_audit_policy_system'; Role = 'ms2025' }
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'ms2025' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'ms2025' }
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'ms2025' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'ms2025' }
        @{ RuleType = 'SecurityOption'; Module = 'community.windows.win_security_policy'; Role = 'ms2025' }
        @{ RuleType = 'UserRight'; Module = 'ansible.windows.win_user_right'; Role = 'ms2025' }
        @{ RuleType = 'WindowsFeature'; Module = 'ansible.windows.win_feature'; Role = 'ms2025' }
        # WindowsClient-10/-11: every one of the twelve rule types the products carry, dispatched
        # from real data. See #98 and #99.
        @{ RuleType = 'AccountPolicy'; Module = 'community.windows.win_security_policy'; Role = 'client10' }
        @{ RuleType = 'AuditPolicy'; Module = 'community.windows.win_audit_policy_system'; Role = 'client10' }
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'client10' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'client10' }
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'client10' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'client10' }
        @{ RuleType = 'SecurityOption'; Module = 'community.windows.win_security_policy'; Role = 'client10' }
        @{ RuleType = 'Service'; Module = 'ansible.windows.win_service_info'; Role = 'client10' }
        @{ RuleType = 'UserRight'; Module = 'ansible.windows.win_user_right'; Role = 'client10' }
        @{ RuleType = 'WindowsFeature'; Module = 'ansible.windows.win_feature'; Role = 'client10' }
        @{ RuleType = 'AccountPolicy'; Module = 'community.windows.win_security_policy'; Role = 'client11' }
        @{ RuleType = 'AuditPolicy'; Module = 'community.windows.win_audit_policy_system'; Role = 'client11' }
        @{ RuleType = 'AuditSetting'; Module = 'AuditSetting'; Role = 'client11' }
        @{ RuleType = 'Permission'; Module = 'ansible.windows.win_acl'; Role = 'client11' }
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'client11' }
        @{ RuleType = 'RootCertificate'; Module = 'community.windows.win_certificate_info'; Role = 'client11' }
        @{ RuleType = 'SecurityOption'; Module = 'community.windows.win_security_policy'; Role = 'client11' }
        @{ RuleType = 'Service'; Module = 'ansible.windows.win_service_info'; Role = 'client11' }
        @{ RuleType = 'UserRight'; Module = 'ansible.windows.win_user_right'; Role = 'client11' }
        @{ RuleType = 'WindowsFeature'; Module = 'ansible.windows.win_feature'; Role = 'client11' }
        # Google-Chrome: both rule types the product carries, dispatched from real data. See #103.
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'chrome' }
        # MS-Edge: its Registry rule type, dispatched from real data. See #103 and #105.
        @{ RuleType = 'Registry'; Module = 'ansible.windows.win_regedit'; Role = 'edge' }
    ) {
        (Get-Variable -Name $Role -ValueOnly).Tasks | Should-BeLikeString "*$Module*"
    }

    # Document and Manual produce nothing for every product; the fixture's own rule ids proving
    # that for WindowsServer-2025, WindowsClient-10/-11, Google-Chrome and MS-Edge too.
    It '<Role> produces no task for its Document or Manual rule' -ForEach @(
        @{ Role = 'dc2025' }
        @{ Role = 'ms2025' }
        @{ Role = 'client10' }
        @{ Role = 'client11' }
        @{ Role = 'chrome' }
        @{ Role = 'edge' }
    ) {
        $tasks = (Get-Variable -Name $Role -ValueOnly).Tasks
        switch ($Role) {
            'client10' {
                $tasks | Should-NotBeLikeString '*V-220701*'
                $tasks | Should-NotBeLikeString '*V-220697*'
            }
            'client11' {
                $tasks | Should-NotBeLikeString '*V-253268*'
                $tasks | Should-NotBeLikeString '*V-253254*'
            }
            'chrome' {
                $tasks | Should-NotBeLikeString '*V-221584*'
            }
            'edge' {
                $tasks | Should-NotBeLikeString '*V-235722*'
                $tasks | Should-NotBeLikeString '*V-235753*'
                $tasks | Should-NotBeLikeString '*V-235755*'
                $tasks | Should-NotBeLikeString '*V-235758*'
                $tasks | Should-NotBeLikeString '*V-251694*'
            }
            default {
                $tasks | Should-NotBeLikeString '*V-277982*'
                $tasks | Should-NotBeLikeString '*V-277985*'
            }
        }
    }

    # #103's map (#105) asked whether the real Edge data agrees with the existing generators'
    # shape field for field. It does, including the org-value case Chrome's fixture also proved -
    # here from a rule where the real org.default.xml already answers it, rather than shipping
    # blank the way Chrome's upstream data does.
    Context 'MS-Edge, whose survey found nothing disagreeing with the existing Registry generator' {

        It 'references the organisation''s answer for the one registry rule that leaves its value unset' {
            $edge.Defaults | Should-BeLikeString '*stig_ms_edge_235766_trackingprevention: 3*'
            $edge.Tasks | Should-BeLikeString '*{{ stig_ms_edge_235766_trackingprevention }}*'
        }

        It 'dispatches the real Registry dscresource variant, not only RegistryPolicyFile' {
            $edge.Tasks | Should-BeLikeString '*ComposeInlineEnabled*'
        }
    }

    # #103's map asked whether the real Chrome data agrees with the Registry generator's shape
    # field for field. It does, including the one field WindowsClient's registry fixture never
    # exercised: a real Registry rule whose value the organisation decides.
    Context 'Google-Chrome, whose survey found nothing disagreeing with the existing Registry generator' {

        It 'references the organisation''s answer for the one registry rule that leaves its value unset' {
            $chrome.Defaults | Should-BeLikeString '*stig_google_chrome_221563_1: oiigbmnaadbkfbmpbfijlflahbdbdgdf*'
            $chrome.Tasks | Should-BeLikeString '*{{ stig_google_chrome_221563_1 }}*'
        }

        It 'dispatches the real Registry dscresource variant, not only RegistryPolicyFile' {
            $chrome.Tasks | Should-BeLikeString '*URLBlocklist*'
        }
    }

    # #99's map asked whether the real WindowsClient-10/-11 data agrees with the existing
    # generators' shape field for field. Ten of the twelve rule types did; Service and UserRight
    # did not, and #100/#101 fixed both. These two shapes are what a real conversion proves that
    # the generators' own direct tests cannot: the rule as PowerStig actually ships it, reaching
    # the role through dispatch rather than a hand-built test double.
    Context 'the two shapes the WindowsClient-10/-11 survey found disagreeing with the existing generators' {

        It 'asserts <Role>''s service in its real Stopped state, not a hardcoded "started"' -ForEach @(
            @{ Role = 'client10' }
            @{ Role = 'client11' }
        ) {
            (Get-Variable -Name $Role -ValueOnly).Tasks | Should-BeLikeString '*services.state is stopped*'
        }

        It 'recognises <Role>''s blank Identity as "nobody holds this right"' -ForEach @(
            @{ Role = 'client10' }
            @{ Role = 'client11' }
        ) {
            $tasks = (Get-Variable -Name $Role -ValueOnly).Tasks
            $tasks | Should-BeLikeString '*Access Credential Manager as a trusted caller*'
            $tasks | Should-MatchString '(?m)^\s*users:\s*$'
        }
    }

    # #95's map asked whether the real 2025 data agrees with 2022's shape field for field. It
    # does: every rule type dispatches the same way, and these two shapes - a registry sub-rule
    # pair where only the second half is an organisation value, and a user right whose Force and
    # Identity are both blank upstream - convert the same way 2022's equivalents do.
    Context 'shapes the WindowsServer-2025 survey confirmed against 2022' {

        It 'puts both halves of the registry sub-rule pair in one block, only one an organisation value' {
            $dc2025.Tasks | Should-BeLikeString '*V-278090 | MEDIUM | DeviceGuard*'
            $dc2025.Tasks | Should-BeLikeString '*V-278090.a | MEDIUM | Set EnableVirtualizationBasedSecurity*'
            $dc2025.Tasks | Should-BeLikeString '*data: 1*'
            $dc2025.Tasks | Should-BeLikeString '*{{ stig_server_2025_278090_b_requireplatformsecurityfeatures }}*'
            $dc2025.Defaults | Should-BeLikeString '*stig_server_2025_278090_b_requireplatformsecurityfeatures: 1*'
        }

        It 'interpolates the organisation''s answer for a user right whose Force and Identity are both blank upstream' {
            $ms2025.Defaults | Should-BeLikeString '*stig_server_2025_278184_deny_access_to_this_computer_from_the_network:*Enterprise Admins*'
            $ms2025.Tasks | Should-BeLikeString '*{{ stig_server_2025_278184_deny_access_to_this_computer_from_the_network }}*'
        }
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
        @{ RuleType = 'SqlDatabase'; Toggle = 'stig_sqlserver_2016_instance_213954_when'; Role = 'sql2016' }
        @{ RuleType = 'SqlProtocol'; Toggle = 'stig_sqlserver_2016_instance_213961_when'; Role = 'sql2016' }
        @{ RuleType = 'SqlLogin'; Toggle = 'stig_sqlserver_2016_instance_213964_when'; Role = 'sql2016' }
        @{ RuleType = 'SqlScriptQuery'; Toggle = 'stig_sqlserver_2016_instance_214028_when'; Role = 'sql2016' }
        @{ RuleType = 'SqlServerConfiguration'; Toggle = 'stig_sqlserver_2016_instance_213957_when'; Role = 'sql2016' }
        @{ RuleType = 'Registry'; Toggle = 'stig_sqlserver_2022_instance_271310_when'; Role = 'sql2022' }
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
    # A site STIG describes a hardened website, not one chosen site, so both loop the role's
    # website list rather than naming a site per rule. See #57.
    Context 'the IIS rule types a site STIG scopes to a website' {

        It 'scopes <RuleType> to every site the role names' -ForEach @(
            @{ RuleType = 'MimeType'; Toggle = 'stig_iissite_10_0_218785_when' }
            @{ RuleType = 'WebConfigurationProperty'; Toggle = 'stig_iissite_10_0_218786_when' }
        ) {
            $site.Tasks | Should-BeLikeString '*IIS:\Sites\{{ item }}*'
            $site.Tasks | Should-MatchString ("loop: '\{\{ stig_iissite_10_0_websites \}\}'\s*\r?\n\s*when: " + $Toggle)
        }

        # The four rule types that reference a website now share one list, so the role answers the
        # question once. The per-rule variables they used to declare are gone.
        It 'declares the one website list all four site rule types read' {
            $site.Defaults | Should-MatchString 'stig_iissite_10_0_websites: \[\]'
            $site.Defaults | Should-NotBeLikeString '*_website:*'
        }
    }

    # An IISServer role used to declare a website variable per MimeType and WebConfigurationProperty
    # rule that no task ever read: the exporter declared by rule type and could not tell a server
    # STIG from a site one. Nothing declares it now, because the server branch references nothing.
    Context 'the website lines a server role never read' {

        It 'declares no website at all for a server STIG' {
            $iis.Defaults | Should-NotBeLikeString '*website*'
        }

        It 'asserts nothing, having no role-scoped list to guard' {
            $iis.Tasks | Should-NotBeLikeString '*names something*'
        }
    }

    # An empty list is a no-op in ansible, so without this a site role whose lists are unanswered
    # hardens nothing and says nothing. See #57.
    Context 'the assert guarding the role-scoped lists' {

        It 'guards <Variable> in <File>' -ForEach @(
            @{ Variable = 'stig_iissite_10_0_websites'; File = 'cat1' }
            @{ Variable = 'stig_iissite_10_0_websites'; File = 'cat2' }
            @{ Variable = 'stig_iissite_10_0_webapppools'; File = 'cat2' }
        ) {
            $site.TaskFile.$File | Should-BeLikeString "*$Variable | length > 0*"
        }

        # tasks/main.yml imports each severity file behind its own tag, so --tags cat2 alone has
        # to assert too.
        It 'repeats the guard in every severity file that has tasks' {
            $site.TaskFile.cat1 | Should-BeLikeString '*stig_iissite_10_0_webapppools | length > 0*'
        }
    }

    # The first role-scoped list more than one rule type reads. Only a conversion can show the one
    # declaration, the five references and the per-severity guard agreeing: each generator's own
    # test sees nothing but its own reference. See #57 and #62.
    Context 'the instances list all five Sql* rule types share' {

        It 'declares it once, however many rule types read it' {
            ([regex]::Matches($sql2016.Defaults, 'stig_sqlserver_2016_instance_instances: \[\]')).Count | Should-Be 1
        }

        # Eight tasks loop it directly; SqlLogin keys on the instance and the login both, so it
        # loops the product of this list and its own instead.
        It 'is what every Sql* task loops over' {
            ([regex]::Matches($sql2016.Tasks, "loop: '\{\{ stig_sqlserver_2016_instance_instances \}\}'")).Count | Should-Be 8
            $sql2016.Tasks | Should-MatchString "loop: '\{\{ stig_sqlserver_2016_instance_instances \| product\(stig_sqlserver_2016_instance_213964_logins\) \| list \}\}'"
        }

        It 'guards it in <File>' -ForEach @(
            @{ File = 'cat1' }
            @{ File = 'cat2' }
        ) {
            $sql2016.TaskFile.$File | Should-BeLikeString '*stig_sqlserver_2016_instance_instances | length > 0*'
        }

        # 2022's only CAT 1 rule is a registry one, which reads no instance at all - the guard is
        # still repeated there, because --tags cat1 alone would otherwise run unguarded.
        It 'repeats the guard in a severity file whose own tasks read no instance' {
            $sql2022.TaskFile.cat1 | Should-BeLikeString '*stig_sqlserver_2022_instance_instances | length > 0*'
        }
    }

    # Both are shared with the Windows STIGs and neither had ever seen a SQL rule, which is a
    # dispatch a direct test cannot exercise: the rule type reaches its generator through the
    # STIG's own XML node name.
    Context 'the two rule types a SQL STIG shares with the Windows ones' {

        It 'dispatches a SQL registry rule to win_regedit' {
            $sql2016.Tasks | Should-BeLikeString '*ansible.windows.win_regedit*'
            $sql2016.Tasks | Should-BeLikeString '*SCHANNEL\Protocols\TLS 1.0\Client*'
        }

        It 'dispatches a SQL security option rule to win_security_policy' {
            $sql2016.Tasks | Should-BeLikeString '*community.windows.win_security_policy*'
            $sql2016.Tasks | Should-BeLikeString '*MACHINE\System\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy\Enabled*'
        }

        It 'produces nothing for the security option upstream marks a duplicate' {
            $sql2016.Tasks | Should-NotBeLikeString '*V-213969*'
        }

        # 2022 states no registry value, leaving each to the organisation - the 2016 STIG has no
        # rule of that shape, so this pairing is why there are two SQL fixtures.
        It 'references the organisation''s answer for a registry rule that states no value' {
            $sql2022.Defaults | Should-BeLikeString '*stig_sqlserver_2022_instance_271310_a_disabledbydefault*: 1*'
            $sql2022.Tasks | Should-BeLikeString '*data: ''{{ stig_sqlserver_2022_instance_271310_a_disabledbydefault*}}''*'
        }

        # The INF Registry Values section holds a type,value pair, not a number, and [int] '4,1'
        # is 41 - the comma read as a thousands separator. No Windows fixture carries one, so a
        # SQL rule is what first showed it. See #77.
        # Unquoted, because 4,1 is already a plain scalar yaml resolves to a string - the 1.1 int
        # pattern separates digits with _, never with a comma. Quoting it would be the one place
        # the converter second-guessed the serializer.
        It 'writes a registry-value security option as the type,value pair' {
            $sql2016.Tasks | Should-BeLikeString '*value: 4,1*'
            $sql2016.Tasks | Should-NotBeLikeString '*value: 41*'
        }
    }

    Context 'SqlDatabase, whose sub-rules share one block' {

        # Ensure is the only field .a to .d agree on, so the block is named from it rather than
        # from the first sub-rule's database. See #62.
        It 'names the block from Ensure' {
            $sql2016.Tasks | Should-BeLikeString '*V-213954 | MEDIUM | Ensure the databases are absent*'
        }

        It 'puts every sub-rule in that one block' {
            ([regex]::Matches($sql2016.Tasks, 'V-213954 \| MEDIUM')).Count | Should-Be 1
            $sql2016.Tasks | Should-BeLikeString '*Ensure Pubs is absent*'
            $sql2016.Tasks | Should-BeLikeString '*Ensure Northwind is absent*'
            $sql2016.Tasks | Should-BeLikeString '*Ensure AdventureWorks is absent*'
        }
    }

    Context 'SqlLogin, whose logins the organisation names' {

        It 'renames the org settings Name attribute to logins' {
            # Matched rather than wildcarded: a yaml flow sequence's brackets are a wildcard
            # character class, and -like would pass on any one of those letters.
            $sql2016.Defaults | Should-MatchString 'stig_sqlserver_2016_instance_213964_logins: \[sa, SqlSvcAppLogin\]'
            $sql2016.Defaults | Should-NotBeLikeString '*213964_name*'
        }

        It 'addresses the instance and the login as the two halves of the product' {
            $sql2016.Tasks | Should-BeLikeString '*InstanceName: ''{{ item.0 }}''*'
            $sql2016.Tasks | Should-BeLikeString '*Name: ''{{ item.1 }}''*'
        }
    }

    # PowerStig hands these over as the strings True and False, which powershell-yaml quotes -
    # and a quoted string is truthy in ansible whichever word it holds. Settled in #69 and
    # asserted per generator; this is the same thing in the rendered YAML. See #70 and #73.
    Context 'the boolean rule fields, as the rendered YAML has them' {

        It 'writes <Field> unquoted and lowercase' -ForEach @(
            @{ Field = 'Enabled: false' }
            @{ Field = 'LoginPasswordPolicyEnforced: true' }
            @{ Field = 'LoginPasswordExpirationEnabled: true' }
            @{ Field = 'LoginMustChangePassword: false' }
        ) {
            $sql2016.Tasks | Should-BeLikeString "*$Field*"
        }

        It 'quotes none of them' {
            $sql2016.Tasks | Should-NotBeLikeString '*: ''False''*'
            $sql2016.Tasks | Should-NotBeLikeString '*: ''True''*'
        }
    }

    Context 'SqlServerConfiguration, the one rule type whose resource name diverges' {

        # SqlServerDsc renamed the resource in v15; PowerStig's rule type keeps the old spelling.
        # See #66 and #72.
        It 'emits the resource name, not the rule type name' {
            $sql2016.Tasks | Should-BeLikeString '*resource_name: SqlConfiguration*'
            $sql2016.Tasks | Should-NotBeLikeString '*resource_name: SqlServerConfiguration*'
        }

        It 'writes the option value as a number rather than a quoted string' {
            $sql2016.Tasks | Should-MatchString 'OptionValue: 0\r?\n'
            $sql2016.Tasks | Should-MatchString 'OptionValue: 1\r?\n'
        }
    }

    Context 'SqlScriptQuery, whose organization value fills a template' {

        # A {0} template substituted into an element of a String[] is a shape no other rule type
        # has. See #65.
        It 'substitutes the answered value into the Variable element' {
            $sql2016.Defaults | Should-BeLikeString '*stig_sqlserver_2016_instance_214029_variablevalue: SqlSysAdmin*'
            $sql2016.Tasks | Should-MatchString 'Variable:\r?\n\s+- saAccountName=\{\{ stig_sqlserver_2016_instance_214029_variablevalue \}\}'
        }

        It 'leaves Variable off the rule that declares none' {
            ([regex]::Matches($sql2016.Tasks, '(?m)^\s*Variable:')).Count | Should-Be 1
        }

        # 2022 ships the same sa-rename SetScript with no Variable to bind $(saAccountName) and no
        # org settings slot to answer - a PowerStig data defect this module reports rather than
        # repairs. Out of scope to fix, in scope to observe.
        It 'warns about the rule whose scripting variable upstream left unbound' {
            ($sql2022.Warnings -join "`n") | Should-BeLikeString '*V-274445*$(saAccountName)*'
        }

        It 'converts that rule anyway, rather than dropping it' {
            $sql2022.Tasks | Should-BeLikeString '*Id: V-274445*'
        }

        It 'warns about nothing in the 2016 STIG, whose scripting variable is bound' {
            @($sql2016.Warnings).Count | Should-Be 0
        }
    }
}

# RHEL-9-2.8, OracleLinux-8-2.4 and OracleLinux-9-1.1 - the first fixtures targeting a Linux host
# rather than a Windows one. See map #78 and #86.
Describe 'New-AnsiblePlaybook for the Linux rule types' {

    Context 'nxFileLine, reaching lineinfile for an ordinary rule' {

        It 'ports ContainsLine and DoesNotContainPattern to line and regexp' {
            $rhel.Tasks | Should-BeLikeString '*ansible.builtin.lineinfile*'
            $rhel.Tasks | Should-BeLikeString '*path: /etc/default/grub*'
            $rhel.Tasks | Should-BeLikeString '*line: GRUB_CMDLINE_LINUX="vsyscall=none"*'
        }

        It 'reaches lineinfile from OracleLinux-8 too, not only RHEL-9' {
            $ol8.Tasks | Should-BeLikeString '*ansible.builtin.lineinfile*'
            $ol8.Tasks | Should-BeLikeString '*path: /proc/sys/crypto/fips_enabled*'
        }
    }

    # V-257779's DoD banner: lineinfile cannot express a multi-line value. See #91.
    Context 'nxFileLine, reaching copy for the one rule whose ContainsLine is multi-line' {

        It 'writes the whole banner through copy, not lineinfile' {
            $rhel.TaskFile.cat2 | Should-BeLikeString '*ansible.builtin.copy*'
            $rhel.TaskFile.cat2 | Should-BeLikeString '*dest: /etc/issue*'
            $rhel.TaskFile.cat2 | Should-MatchString '(?m)^\s*content: \|-'
        }

        It 'gives it generic wording rather than inlining the banner' {
            $rhel.Tasks | Should-BeLikeString '*V-257779 | MEDIUM | Ensure issue contains the required banner text*'
        }
    }

    # OracleLinux-8-2.4 is the only in-scope product carrying nxService. See ADR 0008.
    Context 'nxService, reaching systemd_service' {

        It 'ports Name and the boolean Enabled, omitting the blank State' {
            $ol8.Tasks | Should-BeLikeString '*ansible.builtin.systemd_service*'
            $ol8.Tasks | Should-BeLikeString '*name: kdump*'
            $ol8.Tasks | Should-BeLikeString '*enabled: false*'
        }

        It 'converts the second in-scope rule too' {
            $ol8.Tasks | Should-BeLikeString '*name: autofs*'
        }
    }

    # V-257945.a is the organization-value half of a sub-rule group; .b is ordinary and shares its
    # FilePath, so both land in one block named for the one leaf. See ADR 0009.
    Context 'a value the organization decides' {

        It 'interpolates a defaults/ variable rather than inlining a literal' {
            $rhel.Defaults | Should-BeLikeString '*stig_rhel_9_257945_a_containsline: server 0.us.pool.ntp.mil iburst maxpoll 16*'
            $rhel.Tasks | Should-BeLikeString '*{{ stig_rhel_9_257945_a_containsline }}*'
            $rhel.Tasks | Should-BeLikeString '*{{ stig_rhel_9_257945_a_doesnotcontainpattern }}*'
        }

        It 'guards nothing, because the fixture''s org settings answer the value' {
            $rhel.Tasks | Should-NotBeLikeString '*Assert the organization values*'
        }

        It 'puts both sub-rules in one block named for the shared file' {
            $rhel.Tasks | Should-BeLikeString '*V-257945 | MEDIUM | chrony.conf*'
        }
    }

    # ADR 0009's skip-and-warn guard - each of the four conditions, seen through a real
    # conversion rather than the generator's own direct test.
    Context 'rules PowerStig could not have meant as a line to write' {

        It 'skips the sub-rule whose FilePath is a directory and warns why' {
            $rhel.Tasks | Should-NotBeLikeString '*V-258039.b*'
            ($rhel.Warnings -join "`n") | Should-BeLikeString '*V-258039.b*directory*'
        }

        It 'still converts the ordinary sub-rule sharing that group' {
            $rhel.Tasks | Should-BeLikeString '*V-258039.a*'
        }

        It 'discards the unparsed duplicate rule through the existing duplicate skip, without a task or a warning of its own' {
            $rhel.Tasks | Should-NotBeLikeString '*V-258139*'
        }

        It 'skips a DoesNotContainPattern that compiles in no regex engine and warns why' {
            $ol8.Tasks | Should-NotBeLikeString '*V-248723.d*'
            ($ol8.Warnings -join "`n") | Should-BeLikeString '*V-248723.d*regular expression*'
        }

        It 'skips a ContainsLine carrying a non-ASCII character and warns why' {
            $ol9.Tasks | Should-NotBeLikeString '*V-271572*'
            ($ol9.Warnings -join "`n") | Should-BeLikeString '*V-271572*non-ASCII*'
        }

        It 'still converts the ordinary rule alongside it, so the STIG does not convert to nothing' {
            $ol9.Tasks | Should-BeLikeString '*V-271498*'
        }
    }

    # OracleLinux-9-1.1's three unparsed Permission rules: Permission targets Windows in
    # RuleTypeOsFamily.psd1, so dispatch now skips the whole group before it ever reaches
    # Build-AnsiblePermissionTask - see docs/adr/0010. (Their empty AccessControlEntry would
    # have produced nothing from that adapter too, but the OsFamily check catches it first.)
    Context 'the three unparsed Permission rules OracleLinux-9 carries' {

        It 'produces no win_acl task and no task named for any of them' {
            $ol9.Tasks | Should-NotBeLikeString '*win_acl*'
            $ol9.Tasks | Should-NotBeLikeString '*V-271778*'
            $ol9.Tasks | Should-NotBeLikeString '*V-271827*'
            $ol9.Tasks | Should-NotBeLikeString '*V-271830*'
        }

        It 'warns once for the group, naming every rule id it skipped' {
            $message = ($ol9.Warnings -join "`n")
            $message | Should-BeLikeString '*V-271778, V-271827, V-271830*'
            $message | Should-BeLikeString '*Build-AnsiblePermissionTask targets Windows, not RedHat*'
        }
    }

    # ADR 0006/0007: every Linux task escalates, and it is set inside the adapter's own Body.
    Context 'become, set by the adapter rather than a role-level default' {

        It 'escalates every nxFileLine and nxService task' {
            $rhel.Tasks | Should-MatchString '(?m)^\s*become: true'
            $ol8.Tasks | Should-MatchString '(?m)^\s*become: true'
        }
    }

    # ADR 0007: the Linux role gets its own scaffolding - a different OS assertion, no Server
    # Core fact, no reboot handler.
    Context 'the Linux role scaffolding' {

        It 'asserts the RedHat family and the STIG''s own major version, not Windows' {
            $rhel.TaskMain | Should-BeLikeString "*ansible_os_family == 'RedHat'*"
            $rhel.TaskMain | Should-BeLikeString "*ansible_distribution_major_version == '9'*"
            $rhel.TaskMain | Should-NotBeLikeString '*Windows*'
        }

        It 'tells RHEL and OracleLinux apart by major version, not distribution name alone' {
            $ol8.TaskMain | Should-BeLikeString "*ansible_distribution_major_version == '8'*"
            $ol9.TaskMain | Should-BeLikeString "*ansible_distribution_major_version == '9'*"
        }

        It 'sets no Server Core fact, which does not exist on Linux' {
            $rhel.TaskMain | Should-NotBeLikeString '*Server Core*'
            $rhel.Defaults | Should-NotBeLikeString '*server_core*'
        }

        It 'scaffolds no reboot handler, since no in-scope Linux rule notifies one' {
            $rhel.HandlerMain | Should-NotBeLikeString '*win_reboot*'
        }
    }
}
