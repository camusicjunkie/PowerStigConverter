#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

# These two functions are the only place the sub-rule id convention is written down; CONTEXT.md
# defines the term itself.
Describe 'Test-PowerStigSubRuleId' {

    It 'says an id with a letter suffix is a sub-rule' {
        Invoke-PrivateCommand -Command 'Test-PowerStigSubRuleId' -Splat @{ Id = 'V-254343.b' } | Should-BeTrue
    }

    It 'says an id without one is not' {
        Invoke-PrivateCommand -Command 'Test-PowerStigSubRuleId' -Splat @{ Id = 'V-254343' } | Should-BeFalse
    }
}

Describe 'Get-PowerStigBaseRuleId' {

    It 'drops the sub-rule suffix' {
        Invoke-PrivateCommand -Command 'Get-PowerStigBaseRuleId' -Splat @{ Id = 'V-254343.b' } | Should-Be 'V-254343'
    }

    It 'returns an id that has no suffix unchanged' {
        Invoke-PrivateCommand -Command 'Get-PowerStigBaseRuleId' -Splat @{ Id = 'V-254343' } | Should-Be 'V-254343'
    }
}
