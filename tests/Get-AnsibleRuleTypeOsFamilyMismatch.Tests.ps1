#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Get-Mismatch {
        param ($RuleType, $OsFamily)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ RuleType = $RuleType; OsFamily = $OsFamily } {
            param ($RuleType, $OsFamily)
            Get-AnsibleRuleTypeOsFamilyMismatch -RuleType $RuleType -OsFamily $OsFamily
        }
    }
}

Describe 'Get-AnsibleRuleTypeOsFamilyMismatch' {

    It 'returns nothing when the rule type''s adapter targets this OsFamily' {
        Get-Mismatch -RuleType 'AccountPolicy' -OsFamily 'Windows' | Should-BeNull
    }

    It 'returns the adapter''s own OsFamily when it disagrees' {
        Get-Mismatch -RuleType 'AccountPolicy' -OsFamily 'RedHat' | Should-Be 'Windows'
    }

    It 'returns nothing for a rule type the table says nothing about' {
        Get-Mismatch -RuleType 'ProcessMitigation' -OsFamily 'Windows' | Should-BeNull
    }

    It 'agrees for a Linux-only rule type converted on its own OsFamily' {
        Get-Mismatch -RuleType 'nxFileLine' -OsFamily 'RedHat' | Should-BeNull
    }

    It 'disagrees for a Linux-only rule type converted on the wrong OsFamily' {
        Get-Mismatch -RuleType 'nxFileLine' -OsFamily 'Windows' | Should-Be 'RedHat'
    }
}
