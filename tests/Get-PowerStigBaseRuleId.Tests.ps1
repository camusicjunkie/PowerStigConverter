#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Invoke-Private {
        param ([string] $Command, [hashtable] $Splat)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Command = $Command; Splat = $Splat } {
            param ($Command, $Splat)
            & $Command @Splat
        }
    }
}

# A sub-rule is a STIG rule whose id carries a letter suffix (V-254343.b) because one requirement
# needs several tasks. These two functions are the only place that convention is written down.
Describe 'Test-PowerStigSubRuleId' {

    It 'says an id with a letter suffix is a sub-rule' {
        Invoke-Private -Command 'Test-PowerStigSubRuleId' -Splat @{ Id = 'V-254343.b' } | Should-BeTrue
    }

    It 'says an id without one is not' {
        Invoke-Private -Command 'Test-PowerStigSubRuleId' -Splat @{ Id = 'V-254343' } | Should-BeFalse
    }
}

Describe 'Get-PowerStigBaseRuleId' {

    It 'drops the sub-rule suffix' {
        Invoke-Private -Command 'Get-PowerStigBaseRuleId' -Splat @{ Id = 'V-254343.b' } | Should-Be 'V-254343'
    }

    It 'returns an id that has no suffix unchanged' {
        Invoke-Private -Command 'Get-PowerStigBaseRuleId' -Splat @{ Id = 'V-254343' } | Should-Be 'V-254343'
    }
}
