#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Export-Handler {
        param ($Tasks)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Tasks = $Tasks } {
            param ($Tasks)
            @($Tasks) | Export-AnsibleHandler
        }
    }

    function New-TaskItem {
        param ($Id = 'V-100', $HandlerName = 'apply_ssl_settings', $Bindings = 'Ssl')

        @{
            Rule = [pscustomobject] @{ Id = $Id; Severity = 'medium' }
            Task = [ordered] @{ 'name' = $Id; 'ansible.builtin.set_fact' = @{ stig_sslflags = 'Ssl' } }
            Handler = @([ordered] @{
                'name' = $HandlerName
                'ansible.windows.win_dsc' = [ordered] @{ resource_name = 'SslSettings'; Bindings = $Bindings }
            })
        }
    }
}

Describe 'Export-AnsibleHandler' {

    Context 'the handlers the generated tasks notify' {

        It 'writes the handler under the file handlers/main.yml imports' {
            $content = (Export-Handler -Tasks @(New-TaskItem)).generated -join "`n"

            $content | Should-BeLikeString '*- name: apply_ssl_settings*'
            $content | Should-BeLikeString '*resource_name: SslSettings*'
        }

        # Every rule of the type builds the same handler and notifies it by name, so the same
        # handler arrives once per rule. Writing it once per rule would run the shared write once
        # per rule too.
        It 'writes one entry however many rules notify it' {
            $content = (Export-Handler -Tasks @((New-TaskItem -Id 'V-100'), (New-TaskItem -Id 'V-101'))).generated

            @($content).Count | Should-Be 1
        }

        It 'writes one entry per distinct handler' {
            $content = (Export-Handler -Tasks @((New-TaskItem -HandlerName 'apply_ssl_settings'), (New-TaskItem -HandlerName 'restart_iis'))).generated

            @($content).Count | Should-Be 2
        }

        # A notify names one handler, so two different writes sharing a name means the one that
        # loses never runs - silently, in the generated role, at apply time.
        It 'refuses two different handlers sharing a name' {
            { Export-Handler -Tasks @((New-TaskItem -Bindings 'Ssl'), (New-TaskItem -Bindings 'SslRequireCert')) } |
                Should-Throw -ExceptionMessage '*apply_ssl_settings*'
        }
    }

    Context 'a STIG whose rules generate no handler' {

        # handlers/main.yml imports generated.yml statically, and an import of a file that is not
        # there fails the play - so the file is written whether or not anything filled it.
        It 'still writes a file, holding an empty handler list' {
            $content = (Export-Handler -Tasks @(
                @{ Rule = [pscustomobject] @{ Id = 'V-100'; Severity = 'medium' }
                   Task = [ordered] @{ 'name' = 'V-100' }; Handler = @() }
            )).generated

            @($content).Count | Should-BeGreaterThan 0
            $content | Should-ContainCollection @('[]')
        }
    }
}
