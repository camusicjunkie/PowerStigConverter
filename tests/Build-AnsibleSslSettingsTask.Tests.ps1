#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-SslSettingsRule {
        param ($Id = 'V-218737', $Value = 'Ssl', $Severity = 'medium')

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            Value = $Value
            OrganizationValueRequired = $false
        }
    }

    function Get-SslSettingsItem {
        param ($Rule)

        Invoke-Generator -Generator 'Build-AnsibleSslSettingsTask' -Rule $Rule -StigName 'IISSite-10.0'
    }
}

# The DSC resource writes the whole sslFlags set, so the rules contribute their flags to one
# list and a single handler performs the write. See #52.
Describe 'Build-AnsibleSslSettingsTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleSslSettingsTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'IISSite-10.0' `
        -Factory { New-SslSettingsRule }

    Context 'the task it builds' {

        It 'contributes the rule''s flag to the role''s flag list' {
            $task = (Get-SslSettingsItem -Rule (New-SslSettingsRule)).Task

            $task.'ansible.builtin.set_fact'.stig_iissite_10_0_sslflags |
                Should-Be "{{ (stig_iissite_10_0_sslflags | default([])) + ['Ssl'] }}"
        }

        It 'splits a multi-valued rule into one element per flag' {
            $rule = New-SslSettingsRule -Id 'V-218768' -Value 'Ssl,SslNegotiateCert,SslRequireCert,Ssl128' -Severity 'high'

            (Get-SslSettingsItem -Rule $rule).Task.'ansible.builtin.set_fact'.stig_iissite_10_0_sslflags |
                Should-Be "{{ (stig_iissite_10_0_sslflags | default([])) + ['Ssl', 'SslNegotiateCert', 'SslRequireCert', 'Ssl128'] }}"
        }

        # set_fact is a non-changing module, so without this the notify below never fires.
        It 'reports changed so the notify fires' {
            (Get-SslSettingsItem -Rule (New-SslSettingsRule)).Task.changed_when | Should-BeTrue
        }

        It 'notifies the shared handler' {
            (Get-SslSettingsItem -Rule (New-SslSettingsRule)).Task.notify | Should-Be 'apply_ssl_settings'
        }

        It 'names the task for the rule id, its severity and the flags' {
            (Get-SslSettingsItem -Rule (New-SslSettingsRule)).Task.name |
                Should-Be 'V-218737 | MEDIUM | Ensure SSL settings include Ssl'
        }
    }

    # One write per site with the union of every contributing rule's flags - the same thing
    # PowerStig's own xSslSettings configuration does, deferred to run time.
    Context 'the handler the tasks notify' {

        BeforeAll {
            $script:handler = (Get-SslSettingsItem -Rule (New-SslSettingsRule)).Handler[0]
        }

        It 'is the handler every rule of the type notifies' {
            $handler.name | Should-Be 'apply_ssl_settings'
        }

        It 'uses the SslSettings DSC resource' {
            $handler.'ansible.windows.win_dsc'.resource_name | Should-Be 'SslSettings'
        }

        It 'writes the deduplicated union of the flags' {
            $handler.'ansible.windows.win_dsc'.Bindings | Should-Be '{{ stig_iissite_10_0_sslflags | unique }}'
            $handler.'ansible.windows.win_dsc'.Ensure | Should-Be 'Present'
        }

        # Every SSL rule applies to every site, and the handler is shared, so it cannot use the
        # per-rule website variable MimeType and WebConfigurationProperty declare.
        It 'loops the role''s website list, naming each site bare' {
            $handler.loop | Should-Be '{{ stig_iissite_10_0_websites }}'
            $handler.'ansible.windows.win_dsc'.Name | Should-Be '{{ item }}'
        }
    }

    # The reference above and the declaration Export-AnsibleOrganizationValue writes are two
    # literal strings that only agree by convention. See docs/adr/0004.
    Context 'the website list it declares' {

        It 'declares the same list the handler loops' {
            $rule = New-SslSettingsRule

            $declaration = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rule = $rule } {
                param ($Rule)
                [pscustomobject] @{ PowerStigRule = 'SslSettingsRule'; StigRule = @($Rule) } |
                    Export-AnsibleOrganizationValue -StigName 'IISSite-10.0'
            }

            $declaration.main_default_org | Should-ContainCollection @('stig_iissite_10_0_websites: []')
        }
    }
}
