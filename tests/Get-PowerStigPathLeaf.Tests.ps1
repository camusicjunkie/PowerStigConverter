#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Get-PowerStigPathLeaf' {

    It 'returns the segment after the last forward slash' {
        Invoke-PrivateCommand -Command 'Get-PowerStigPathLeaf' -Splat @{ Path = '/system.webServer/security/requestFiltering' } |
            Should-Be 'requestFiltering'
    }

    It 'returns the segment after the last slash for a value with only one' {
        Invoke-PrivateCommand -Command 'Get-PowerStigPathLeaf' -Splat @{ Path = 'binary/octet-stream' } |
            Should-Be 'octet-stream'
    }

    It 'returns the whole value when there is no slash' {
        Invoke-PrivateCommand -Command 'Get-PowerStigPathLeaf' -Splat @{ Path = 'octet-stream' } |
            Should-Be 'octet-stream'
    }
}
