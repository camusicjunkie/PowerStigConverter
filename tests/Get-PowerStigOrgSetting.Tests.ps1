#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'

    function Get-OrgSetting {
        param ($StigName, $Path)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ StigName = $StigName; Path = $Path } {
            param ($StigName, $Path)
            Get-PowerStigOrgSetting -StigName $StigName -Path $Path
        }
    }
}

Describe 'Get-PowerStigOrgSetting' {

    # The org settings used to be re-read and re-parsed once per rule, from two places. Loading
    # them once into a map by rule id is what gives the conversion a single point at which the
    # inputs can be judged complete.
    Context 'loading a STIG org settings file' {

        It 'keys the settings by rule id' {
            $settings = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            $settings.Keys | Should-ContainCollection 'V-201'
            $settings.Keys | Should-ContainCollection 'V-202'
        }

        It 'keeps the node so a caller can read whichever attributes its rule type needs' {
            $settings = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            $settings['V-201'].PolicyValue | Should-Be '15'
        }

        # PowerStig ships a setting blank when it cannot guess the value. That is data, not an
        # absence - the entry is there, and the distinction is what lets an unanswered setting
        # be reported differently from a missing one.
        It 'keeps an entry whose value is blank' {
            $settings = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            $settings.ContainsKey('V-202') | Should-BeTrue
            $settings['V-202'].PolicyValue | Should-Be ''
        }

        It 'has no entry for a rule the file does not cover' {
            $settings = Get-OrgSetting -StigName 'WindowsClient-11' -Path $fixtureRoot

            $settings.ContainsKey('V-999') | Should-BeFalse
        }
    }

    Context 'a file with no settings in it' {

        It 'returns an empty map rather than nothing' {
            $settings = Get-OrgSetting -StigName 'WindowsServer-2022-MS' -Path $fixtureRoot

            $settings -is [hashtable] | Should-BeTrue
            $settings.Count | Should-Be 0
        }
    }

    # The path matters: reading from a fixed location however the command was called is what
    # made a STIG kept anywhere else generate tasks with the value missing.
    Context 'reading from the path it was given' {

        It 'throws when no org settings file matches the STIG name there' {
            { Get-OrgSetting -StigName 'NotAStig-1.0' -Path $fixtureRoot } |
                Should -Throw -ExpectedMessage '*NotAStig-1.0*'
        }
    }
}
