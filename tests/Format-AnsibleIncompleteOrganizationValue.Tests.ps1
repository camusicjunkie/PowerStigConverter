#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Format-IncompleteValue {
        param ($Variable, $StigName = 'WindowsServer-2022-MS')

        Invoke-PrivateCommand -Command 'Format-AnsibleIncompleteOrganizationValue' -Splat @{
            Variable = $Variable; StigName = $StigName
        }
    }

    function New-IncompleteVariable {
        param ($RuleId = 'V-100', $RuleType = 'AccountPolicy', $Field = 'PolicyValue', $Status = 'Unanswered')

        [pscustomobject] @{ RuleId = $RuleId; RuleType = $RuleType; Field = $Field; Status = $Status }
    }
}

Describe 'Format-AnsibleIncompleteOrganizationValue' {

    Context 'the counts in the summary line' {

        It 'reports only unanswered when there is no missing entry' {
            $message = Format-IncompleteValue -Variable @(New-IncompleteVariable -Status 'Unanswered')

            $message | Should-BeLikeString "*(1 unanswered)*"
        }

        It 'reports only missing when there is no unanswered value' {
            $message = Format-IncompleteValue -Variable @(New-IncompleteVariable -Status 'Missing')

            $message | Should-BeLikeString "*(1 missing)*"
        }

        # Both remedies differ, so a reader with one of each needs to see both counts.
        It 'reports both counts, unanswered before missing' {
            $message = Format-IncompleteValue -Variable @(
                (New-IncompleteVariable -RuleId 'V-100' -Status 'Unanswered')
                (New-IncompleteVariable -RuleId 'V-101' -Status 'Missing')
            )

            $message | Should-BeLikeString "*(1 unanswered and 1 missing)*"
        }

        It 'names the stig the settings belong to' {
            $message = Format-IncompleteValue -Variable @(New-IncompleteVariable) -StigName 'WindowsServer-2022-MS'

            $message | Should-BeLikeString "*'WindowsServer-2022-MS'*"
        }
    }

    Context 'the remedy per line' {

        It 'tells an unanswered value to be filled in' {
            $message = Format-IncompleteValue -Variable @(New-IncompleteVariable -Status 'Unanswered')

            $message | Should-BeLikeString '*left blank for the organization to decide*'
        }

        # Missing means the org settings file has no entry at all for the rule, which is a
        # different problem than one left blank on purpose.
        It 'tells a missing value it may be the wrong stig version' {
            $message = Format-IncompleteValue -Variable @(New-IncompleteVariable -Status 'Missing')

            $message | Should-BeLikeString '*no entry in the org settings file - it may not match this STIG version*'
        }

        It 'names the rule id, rule type and field on the line' {
            $message = Format-IncompleteValue -Variable @(
                New-IncompleteVariable -RuleId 'V-254239' -RuleType 'AccountPolicy' -Field 'PolicyValue'
            )

            $message | Should-BeLikeString '*V-254239*AccountPolicy*PolicyValue:*'
        }
    }

    Context 'the closing instruction' {

        It 'points at the org settings file and the override switch' {
            $message = Format-IncompleteValue -Variable @(New-IncompleteVariable)

            $message | Should-BeLikeString '*Answer these in the org settings file*'
            $message | Should-BeLikeString '*-AllowIncompleteOrganizationValue*'
        }
    }
}
