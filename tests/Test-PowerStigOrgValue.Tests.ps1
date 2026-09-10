#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Test-OrgValue {
        param ($NodeValue, $RuleId)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ NodeValue = $NodeValue; RuleId = $RuleId } {
            param ($NodeValue, $RuleId)
            Test-PowerStigOrgValue -NodeValue $NodeValue -RuleId $RuleId
        }
    }
}

Describe 'Test-PowerStigOrgValue' {

    # PowerStig ships org settings files with some values deliberately left blank for the
    # implementing site to fill in. This reports whether a value is still blank, so the caller
    # can skip the rule instead of emitting a variable with nothing in it.
    Context 'a value the site has not filled in' {

        It 'reports <Reason> as needing attention' -ForEach @(
            @{ Reason = 'an empty string'; NodeValue = '' }
            @{ Reason = 'a null value'; NodeValue = $null }
        ) {
            Test-OrgValue -NodeValue $NodeValue -RuleId 'V-254239' | Should-BeTrue
        }

        It 'warns which rule id needs filling in, so the user can go and fix it' {
            # The warning is raised inside the module scope, so capture it from the stream.
            $captured = InModuleScope -ModuleName PowerStigConverter {
                Test-PowerStigOrgValue -NodeValue '' -RuleId 'V-254239' 3>&1 |
                    Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            }

            $captured.Message | Should-BeLikeString '*V-254239*'
        }
    }

    Context 'a value the site has filled in' {

        It 'reports <NodeValue> as ready to use' -ForEach @(
            @{ NodeValue = '60' }
            @{ NodeValue = 'Administrators' }
            @{ NodeValue = '0' }
        ) {
            Test-OrgValue -NodeValue $NodeValue -RuleId 'V-254239' | Should-BeFalse
        }

        It 'does not warn about a value that is present' {
            $captured = InModuleScope -ModuleName PowerStigConverter {
                Test-PowerStigOrgValue -NodeValue '60' -RuleId 'V-254239' 3>&1 |
                    Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            }

            $captured | Should-BeNull
        }
    }
}
