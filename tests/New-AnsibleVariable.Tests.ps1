#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    # Every name this function builds starts from the STIG's variable prefix. The README
    # documents WindowsServer-2022-MS as stig_server_2022, so that is the prefix the expected
    # values below are written against.
    $script:stig = 'WindowsServer-2022-MS'
    $script:prefix = 'stig_server_2022'

    function Invoke-NewAnsibleVariable {
        param ([hashtable] $Splat)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Splat = $Splat } {
            param ($Splat)
            New-AnsibleVariable @Splat
        }
    }
}

Describe 'New-AnsibleVariable' {

    Context 'the conditional toggle a task is guarded by' {

        It 'names a when-variable from the prefix and the rule id' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254239'
                Type = 'Conditional'
                StigName = $stig
            }

            $variable | Should-Be "${prefix}_254239_when"
        }

        It 'emits the same name with a default of true as a defaults-file line' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254239'
                Type = 'ConditionalValue'
                StigName = $stig
            }

            $variable | Should-Be "${prefix}_254239_when: true"
        }

        It 'flattens a sub-rule suffix, which is not legal in an ansible variable name' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254343.b'
                Type = 'Conditional'
                StigName = $stig
            }

            $variable | Should-Be "${prefix}_254343_b_when"
        }
    }

    Context 'organisation values the site has to decide' {

        It 'renders a jinja reference a task can interpolate' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254239'
                TaskName = 'Maximum password age'
                Type = 'Organization'
                StigName = $stig
            }

            $variable | Should-Be "{{ ${prefix}_254239_maximum_password_age }}"
        }

        It 'renders the matching defaults-file line with the value from the org settings' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254239'
                TaskName = 'Maximum password age'
                NodeValue = 60
                Type = 'OrganizationValue'
                StigName = $stig
            }

            $variable | Should-Be "${prefix}_254239_maximum_password_age: 60"
        }

        It 'strips punctuation out of a policy name so the variable name stays legal' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254443'
                TaskName = 'Accounts: Rename administrator account'
                Type = 'Organization'
                StigName = $stig
            }

            $variable | Should-Be "{{ ${prefix}_254443_accounts_rename_administrator_account }}"
        }

        It 'names the group toggle with the bare prefix' {
            $variable = Invoke-NewAnsibleVariable @{
                Type = 'OrganizationValueGroup'
                StigName = $stig
            }

            $variable | Should-Be $prefix
        }
    }

    # Org values are STIG prose. Left bare, a value containing ": " parses as a nested mapping
    # and the defaults file stops being loadable at all - the DoD logon notice is the worst
    # offender. Anything that cannot stand as a plain yaml scalar has to be quoted.
    Context 'values that would otherwise break the yaml' {

        It 'quotes a value containing a colon and a space' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-254442'
                TaskName = 'Legal Notice'
                NodeValue = 'You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS: you consent to monitoring.'
                Type = 'OrganizationValue'
                StigName = $stig
            }

            $variable | Should-BeLikeString "*: 'You are accessing*this IS: you consent to monitoring.'"
        }

        It 'doubles an embedded single quote so the quoting survives' {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-1'
                TaskName = 'Notice'
                NodeValue = "the system owner's consent: granted"
                Type = 'OrganizationValue'
                StigName = $stig
            }

            $variable | Should-BeLikeString "*'the system owner''s consent: granted'"
        }

        It 'quotes a value that <Reason>' -ForEach @(
            @{ Reason = 'has leading whitespace'; NodeValue = ' leading' }
            @{ Reason = 'has trailing whitespace'; NodeValue = 'trailing ' }
            @{ Reason = 'opens with a yaml comment marker'; NodeValue = '#not a comment' }
            @{ Reason = 'opens with a yaml anchor marker'; NodeValue = '&anchor' }
            @{ Reason = 'opens with a yaml block scalar marker'; NodeValue = '|block' }
        ) {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-1'
                TaskName = 'Setting'
                NodeValue = $NodeValue
                Type = 'OrganizationValue'
                StigName = $stig
            }

            $variable | Should-MatchString ": '.*'$"
        }

        It 'leaves a plain value alone, so <NodeValue> stays the type yaml reads it as' -ForEach @(
            @{ NodeValue = 60 }
            @{ NodeValue = 0 }
            @{ NodeValue = 'Administrators' }
            @{ NodeValue = 'Administrators,Guests' }
        ) {
            $variable = Invoke-NewAnsibleVariable @{
                TaskId = 'V-1'
                TaskName = 'Setting'
                NodeValue = $NodeValue
                Type = 'OrganizationValue'
                StigName = $stig
            }

            $variable | Should-Be "${prefix}_1_setting: $NodeValue"
        }
    }
}
