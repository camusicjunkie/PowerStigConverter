#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Get-AnsibleRoleName' {

    It 'names <Expected> for <StigName>' -ForEach @(
        @{ StigName = 'WindowsServer-2022-MS'; Expected = 'windowsserver_2022_ms' }
        @{ StigName = 'WindowsClient-11'; Expected = 'windowsclient_11' }
        @{ StigName = 'IISServer-10.0'; Expected = 'iisserver_10_0' }
    ) {
        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
            param ($Name)
            Get-AnsibleRoleName -StigName $Name
        } | Should-Be $Expected
    }

    # 'All' is a scope, not a release, so no role carries it. See docs/adr/0019.
    It 'drops the All scope for <StigName>' -ForEach @(
        @{ StigName = 'WindowsDefender-All'; Expected = 'windowsdefender' }
        @{ StigName = 'WindowsFirewall-All'; Expected = 'windowsfirewall' }
        @{ StigName = 'FireFox-All'; Expected = 'firefox' }
    ) {
        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Name = $StigName } {
            param ($Name)
            Get-AnsibleRoleName -StigName $Name
        } | Should-Be $Expected
    }

    # Anchored on the dash, as the variable prefix is, so a name that merely ends in those letters keeps them.
    It 'keeps the letters of a product whose own name ends in All' {
        InModuleScope -ModuleName PowerStigConverter {
            Get-AnsibleRoleName -StigName 'WindowsFirewall'
        } | Should-Be 'windowsfirewall'
    }
}
