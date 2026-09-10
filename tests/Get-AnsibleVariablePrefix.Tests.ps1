#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Get-AnsibleVariablePrefix' {

    # Every variable in a generated role is named from this prefix, and the plaster
    # scaffolding is handed the same value, so the two must agree. The expected prefixes
    # below are the ones the README documents.
    Context 'deriving a prefix from the STIG name' {

        It 'derives <Expected> from <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2022-MS'; Expected = 'stig_server_2022' }
            @{ StigName = 'WindowsServer-2012R2-DC'; Expected = 'stig_server_2012r2' }
            @{ StigName = 'WindowsClient-11'; Expected = 'stig_client_11' }
        ) {
            InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
                param ($Name)
                Get-AnsibleVariablePrefix -StigName $Name
            } | Should-Be $Expected
        }

        It 'keeps the release suffix so 2012 and 2012R2 do not collapse together' {
            $prefixes = InModuleScope -ModuleName PowerStigConverter {
                Get-AnsibleVariablePrefix -StigName 'WindowsServer-2012-DC'
                Get-AnsibleVariablePrefix -StigName 'WindowsServer-2012R2-DC'
            }

            $prefixes[0] | Should-NotBe $prefixes[1]
        }
    }

    Context 'application STIGs, which are not tied to one Windows release' {

        It 'derives <Expected> from <StigName> by sanitising the name' -ForEach @(
            @{ StigName = 'IISServer-10.0'; Expected = 'stig_iisserver_10_0' }
            @{ StigName = 'DotNetFramework-4'; Expected = 'stig_dotnetframework_4' }
            @{ StigName = 'SqlServer-2016-Instance'; Expected = 'stig_sqlserver_2016_instance' }
            @{ StigName = 'WindowsDefender-All'; Expected = 'stig_windowsdefender_all' }
        ) {
            InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
                param ($Name)
                Get-AnsibleVariablePrefix -StigName $Name
            } | Should-Be $Expected
        }
    }

    Context 'the result has to be a legal ansible variable name' {

        It 'emits only lowercase letters, digits and underscores for <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2022-MS' }
            @{ StigName = 'IISSite-10.0' }
            @{ StigName = 'Office-365ProPlus' }
            @{ StigName = 'MS-Edge' }
            @{ StigName = 'Ubuntu-18.04' }
            @{ StigName = 'Adobe-AcrobatReader' }
        ) {
            $prefix = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
                param ($Name)
                Get-AnsibleVariablePrefix -StigName $Name
            }

            $prefix | Should-MatchString '^[a-z][a-z0-9_]*$'
        }

        It 'never leaves a trailing underscore, even when the name ends in punctuation' {
            $prefix = InModuleScope -ModuleName PowerStigConverter {
                Get-AnsibleVariablePrefix -StigName 'Office-System2016.'
            }

            $prefix | Should-Be 'stig_office_system2016'
        }
    }
}
