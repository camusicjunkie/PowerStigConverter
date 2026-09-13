#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    # Every name starts from the STIG's variable prefix. The README documents
    # WindowsServer-2022-MS as stig_server_2022, so that is what the expected values use.
    $script:stig = 'WindowsServer-2022-MS'
    $script:prefix = 'stig_server_2022'
}

Describe 'Get-AnsibleToggleName' {

    Context 'the conditional toggle a task is guarded by' {

        It 'names it from the prefix and the rule id' {
            Invoke-PrivateCommand -Command 'Get-AnsibleToggleName' -Splat @{ TaskId = 'V-254239'; StigName = $stig } |
                Should-Be "${prefix}_254239_when"
        }

        # A toggle switches a whole requirement off, so a sub-rule takes its base id - and the
        # suffix is not legal in an ansible variable name either way.
        It 'flattens a sub-rule suffix' {
            Invoke-PrivateCommand -Command 'Get-AnsibleToggleName' -Splat @{ TaskId = 'V-254343.b'; StigName = $stig } |
                Should-Be "${prefix}_254343_b_when"
        }
    }
}

Describe 'New-AnsibleToggleLine' {

    It 'declares the toggle on' {
        Invoke-PrivateCommand -Command 'New-AnsibleToggleLine' -Splat @{ TaskId = 'V-254239'; StigName = $stig } |
            Should-Be "${prefix}_254239_when: true"
    }
}

Describe 'Get-AnsibleRegisterName' {

    Context 'the variable a gather task registers its result in' {

        It 'names it from the prefix, the rule id and the suffix the caller asked for' {
            Invoke-PrivateCommand -Command 'Get-AnsibleRegisterName' -Splat @{
                TaskId = 'V-160'; StigName = $stig; Suffix = 'service_info'
            } | Should-Be "${prefix}_160_service_info"
        }

        # A register is named for the rule it belongs to, so a sub-rule id reaches it the same way
        # it reaches every other variable name.
        It 'flattens a sub-rule suffix, which is not legal in an ansible variable name' {
            Invoke-PrivateCommand -Command 'Get-AnsibleRegisterName' -Splat @{
                TaskId = 'V-254343.b'; StigName = $stig; Suffix = 'certificate_info'
            } | Should-Be "${prefix}_254343_b_certificate_info"
        }
    }
}

Describe 'Get-AnsibleVariableName' {

    Context 'organization values the organization decides' {

        It 'names it from the prefix, the rule id and the task name' {
            Invoke-PrivateCommand -Command 'Get-AnsibleVariableName' -Splat @{
                TaskId = 'V-254239'; TaskName = 'Account lockout duration'; StigName = $stig
            } | Should-Be "${prefix}_254239_account_lockout_duration"
        }

        It 'strips punctuation so the variable name stays legal' {
            Invoke-PrivateCommand -Command 'Get-AnsibleVariableName' -Splat @{
                TaskId = 'V-254239'; TaskName = 'Accounts: Guest account status'; StigName = $stig
            } | Should-Be "${prefix}_254239_accounts_guest_account_status"
        }
    }
}

Describe 'Get-AnsibleVariableReference' {

    It 'renders a jinja reference a task can interpolate' {
        Invoke-PrivateCommand -Command 'Get-AnsibleVariableReference' -Splat @{
            TaskId = 'V-254239'; TaskName = 'Account lockout duration'; StigName = $stig
        } | Should-Be "{{ ${prefix}_254239_account_lockout_duration }}"
    }

    # The declaration in defaults/, the reference in tasks/ and the assert that guards it have to
    # name the same variable.
    It 'references exactly the name the declaration uses' {
        $splat = @{ TaskId = 'V-254239'; TaskName = 'Account lockout duration'; StigName = $stig }

        $name = Invoke-PrivateCommand -Command 'Get-AnsibleVariableName' -Splat $splat
        $reference = Invoke-PrivateCommand -Command 'Get-AnsibleVariableReference' -Splat $splat

        $reference | Should-Be "{{ $name }}"
    }
}

Describe 'New-AnsibleVariableLine' {

    It 'declares the variable with the value from the org settings' {
        Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
            TaskId = 'V-254239'; TaskName = 'Account lockout duration'; StigName = $stig; NodeValue = 60
        } | Should-Be "${prefix}_254239_account_lockout_duration: 60"
    }

    # Org values are STIG text, and some of them - the DoD legal notice above all - contain a
    # colon and a space, which yaml reads as a nested mapping.
    Context 'values that would otherwise break the yaml' {

        It 'quotes a value that <Reason>' -ForEach @(
            @{ Reason = 'contains a colon and a space'; NodeValue = 'Warning: you are being watched'; Expected = "'Warning: you are being watched'" }
            @{ Reason = 'has leading whitespace'; NodeValue = ' leading'; Expected = "' leading'" }
            @{ Reason = 'has trailing whitespace'; NodeValue = 'trailing '; Expected = "'trailing '" }
            @{ Reason = 'opens with a yaml comment marker'; NodeValue = '#not a comment'; Expected = "'#not a comment'" }
            @{ Reason = 'opens with a yaml anchor marker'; NodeValue = '&anchor'; Expected = "'&anchor'" }
            @{ Reason = 'opens with a yaml block scalar marker'; NodeValue = '|block'; Expected = "'|block'" }
        ) {
            Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
                TaskId = 'V-1'; TaskName = 'name'; StigName = $stig; NodeValue = $NodeValue
            } | Should-Be "${prefix}_1_name: $Expected"
        }

        It 'doubles an embedded single quote so the quoting survives' {
            Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
                TaskId = 'V-1'; TaskName = 'name'; StigName = $stig; NodeValue = "Don't: really"
            } | Should-Be "${prefix}_1_name: 'Don''t: really'"
        }

        It 'leaves <NodeValue> alone, so it stays the type yaml reads it as' -ForEach @(
            @{ NodeValue = 60 }
            @{ NodeValue = 0 }
            @{ NodeValue = 'Administrators' }
            @{ NodeValue = 'Administrators,Guests' }
        ) {
            Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
                TaskId = 'V-1'; TaskName = 'name'; StigName = $stig; NodeValue = $NodeValue
            } | Should-Be "${prefix}_1_name: $NodeValue"
        }
    }

    # A value the task needs as a list is split before it gets here and written as a flow
    # sequence, so the whole variable can be interpolated as one. See docs/adr/0003.
    Context 'a value the task needs as a list' {

        It 'writes it as a yaml flow sequence' {
            Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
                TaskId = 'V-1'; TaskName = 'name'; StigName = $stig; NodeValue = [string[]] @('Administrators', 'Guests')
            } | Should-Be "${prefix}_1_name: [Administrators, Guests]"
        }

        It 'writes a single-valued list as a sequence too' {
            Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
                TaskId = 'V-1'; TaskName = 'name'; StigName = $stig; NodeValue = [string[]] @('Administrators')
            } | Should-Be "${prefix}_1_name: [Administrators]"
        }

        # Inside a flow sequence a comma ends the element, so it needs quoting where a plain
        # scalar would not.
        It 'quotes an element containing a comma' {
            Invoke-PrivateCommand -Command 'New-AnsibleVariableLine' -Splat @{
                TaskId = 'V-1'; TaskName = 'name'; StigName = $stig; NodeValue = [string[]] @('a,b', 'c')
            } | Should-Be "${prefix}_1_name: ['a,b', c]"
        }
    }
}

Describe 'Get-AnsibleRoleVariableName' {

    Context 'a variable declared once for the whole role' {

        # No rule id: every rule of the type reads the same list of IIS sites, so a per-rule name
        # would declare the same answer once per rule and let them drift apart.
        It 'names it from the prefix and the task name alone' {
            Invoke-PrivateCommand -Command 'Get-AnsibleRoleVariableName' -Splat @{ TaskName = 'websites'; StigName = $stig } |
                Should-Be "${prefix}_websites"
        }

        It 'strips punctuation so the variable name stays legal' {
            Invoke-PrivateCommand -Command 'Get-AnsibleRoleVariableName' -Splat @{ TaskName = 'App Pools (IIS)'; StigName = $stig } |
                Should-Be "${prefix}_app_pools_iis"
        }
    }
}

Describe 'Get-AnsibleRoleVariableReference' {

    It 'references exactly the name the declaration uses' {
        $splat = @{ TaskName = 'websites'; StigName = $stig }

        $name = Invoke-PrivateCommand -Command 'Get-AnsibleRoleVariableName' -Splat $splat
        $declaration = Invoke-PrivateCommand -Command 'New-AnsibleRoleVariableLine' -Splat $splat

        Invoke-PrivateCommand -Command 'Get-AnsibleRoleVariableReference' -Splat $splat | Should-Be "{{ $name }}"
        $declaration | Should-Be "${name}: []"
    }
}

Describe 'New-AnsibleRoleVariableLine' {

    # Nothing in the STIG answers it - the site names its own IIS sites - and the tasks that read
    # one loop over it, so an empty list rather than a blank scalar.
    It 'declares it as an empty list for the site to fill in' {
        Invoke-PrivateCommand -Command 'New-AnsibleRoleVariableLine' -Splat @{ TaskName = 'websites'; StigName = $stig } |
            Should-Be "${prefix}_websites: []"
    }
}
