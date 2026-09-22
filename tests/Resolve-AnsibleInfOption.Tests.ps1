#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Resolve-InfOption {
        param ($OptionName, $Value)

        $params = @{ OptionName = $OptionName }
        if ($PSBoundParameters.ContainsKey('Value')) { $params['Value'] = $Value }

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Params = $params } {
            param ($Params)
            Resolve-AnsibleInfOption @Params
        }
    }
}

Describe 'Resolve-AnsibleInfOption' {

    Context 'section and key' {

        It 'reads the section and key off AccountPolicyData.psd1' {
            $result = Resolve-InfOption -OptionName 'Maximum password age'

            $result.Section | Should-Be 'System Access'
            $result.Key | Should-Be 'MaximumPasswordAge'
        }

        It 'reads the section and key off SecurityOptionData.psd1' {
            $result = Resolve-InfOption -OptionName 'Accounts: Guest account status'

            $result.Section | Should-Be 'System Access'
            $result.Key | Should-Be 'EnableGuestAccount'
        }

        It 'mangles a slash in the option name' {
            $result = Resolve-InfOption -OptionName 'Accounts: Block Microsoft accounts'

            $result.Key | Should-BeLikeString '*NoConnectedUser'
        }

        It 'mangles whitespace in the option name' {
            $result = Resolve-InfOption -OptionName 'Domain member: Maximum machine account password age'

            $result.Key | Should-BeLikeString '*MaximumPasswordAge'
        }

        It 'mangles a colon in the option name' {
            $result = Resolve-InfOption -OptionName 'Accounts: Guest account status'

            $result.Section | Should-Be 'System Access'
        }
    }

    Context 'a bare-number Option entry' {

        It 'maps <Value> to <Expected> as an int' -ForEach @(
            @{ Value = 'Enabled'; Expected = 1 }
            @{ Value = 'Disabled'; Expected = 0 }
        ) {
            $result = Resolve-InfOption -OptionName 'Accounts: Guest account status' -Value $Value

            $result.Value | Should-Be $Expected
            $result.Value -is [int] | Should-BeTrue
        }

        It 'looks the mapping up by the value asked for, not by the property name' {
            $enabled = Resolve-InfOption -OptionName 'Accounts: Guest account status' -Value 'Enabled'
            $disabled = Resolve-InfOption -OptionName 'Accounts: Guest account status' -Value 'Disabled'

            $enabled.Value | Should-NotBe $disabled.Value
        }
    }

    Context 'a type,value Option entry in Registry Values' {

        It 'keeps the mapped value a string, not an int' {
            $result = Resolve-InfOption -OptionName 'Accounts: Block Microsoft accounts' `
                -Value 'Users cant add Microsoft accounts'

            $result.Value | Should-Be '4,1'
            $result.Value -is [string] | Should-BeTrue
        }
    }

    Context 'no value asked for' {

        It 'reports section and key without mapping a value' {
            $result = Resolve-InfOption -OptionName 'Maximum password age'

            $result.Value | Should-BeNull
        }
    }
}
