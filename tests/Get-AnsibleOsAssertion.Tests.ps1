#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Get-AnsibleOsAssertion' {

    # tasks/main.yml asserts the target OS by matching ansible_distribution against Pattern,
    # and names the supported OS in the failure message using Description. ansible_distribution
    # reports the full product name and edition - "Microsoft Windows Server 2022 Datacenter" -
    # so Pattern has to be the leading product name only. The expected values below are the
    # ones the README documents.
    Context 'Windows Server STIGs' {

        It 'asserts <Expected> for <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2022-MS'; Expected = 'Microsoft Windows Server 2022' }
            @{ StigName = 'WindowsServer-2022-DC'; Expected = 'Microsoft Windows Server 2022' }
            @{ StigName = 'WindowsServer-2012R2-DC'; Expected = 'Microsoft Windows Server 2012 R2' }
        ) {
            $assertion = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
                param ($Name)
                Get-AnsibleOsAssertion -StigName $Name
            }

            $assertion.Pattern | Should-Be $Expected
        }

        It 'separates the R-release from the year so the product name reads as Ansible reports it' {
            $assertion = InModuleScope -ModuleName PowerStigConverter {
                Get-AnsibleOsAssertion -StigName 'WindowsServer-2012R2-DC'
            }

            $assertion.Description | Should-Be 'Windows Server 2012 R2'
        }
    }

    Context 'Windows Client STIGs' {

        It 'asserts <Expected> for <StigName>' -ForEach @(
            @{ StigName = 'WindowsClient-11'; Expected = 'Microsoft Windows 11' }
            @{ StigName = 'WindowsClient-10'; Expected = 'Microsoft Windows 10' }
        ) {
            $assertion = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
                param ($Name)
                Get-AnsibleOsAssertion -StigName $Name
            }

            $assertion.Pattern | Should-Be $Expected
        }

        It 'does not put the word Server in a client product name' {
            $assertion = InModuleScope -ModuleName PowerStigConverter {
                Get-AnsibleOsAssertion -StigName 'WindowsClient-11'
            }

            $assertion.Description | Should-NotMatchString 'Server'
        }
    }

    Context 'application STIGs, which are not tied to one Windows release' {

        It 'asserts only that the host is Windows for <StigName>' -ForEach @(
            @{ StigName = 'IISServer-10.0' }
            @{ StigName = 'SqlServer-2022-Instance' }
            @{ StigName = 'DotNetFramework-4' }
        ) {
            $assertion = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
                param ($Name)
                Get-AnsibleOsAssertion -StigName $Name
            }

            $assertion.Pattern | Should-Be 'Microsoft Windows'
            $assertion.Description | Should-Be 'Windows'
        }
    }

    Context 'the shape the scaffolding consumes' {

        It 'returns a Pattern that is the Description prefixed with the vendor' {
            $assertion = InModuleScope -ModuleName PowerStigConverter {
                Get-AnsibleOsAssertion -StigName 'WindowsServer-2025-MS'
            }

            $assertion.Pattern | Should-Be ('Microsoft {0}' -f $assertion.Description)
        }
    }
}
