#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Add-OrgAssert {
        param ($Task, $Resolution)

        Invoke-PrivateCommand -Command 'Add-AnsibleOrganizationValueAssert' -Splat @{ Task = $Task; Resolution = $Resolution }
    }

    function New-Assert {
        [ordered] @{
            'name' = 'Assert the organization values for V-100 have been filled in'
            'ansible.builtin.assert' = [ordered] @{ 'that' = @('stig_server_2022_100_maximum_password_age | default("", true) | length > 0') }
        }
    }
}

Describe 'Add-AnsibleOrganizationValueAssert' {

    Context 'a resolution with nothing to guard' {

        It 'returns the task untouched when the resolution has no assert' {
            $task = [ordered] @{ 'name' = 'V-100 | MEDIUM | Maximum password age' }
            $resolution = [pscustomobject] @{ Assert = $null }

            Add-OrgAssert -Task $task -Resolution $resolution | Should-Be $task
        }
    }

    Context 'a resolution with an assert' {

        It 'wraps the task in a block named for it' {
            $task = [ordered] @{ 'name' = 'V-100 | MEDIUM | Maximum password age' }
            $resolution = [pscustomobject] @{ Assert = New-Assert }

            $wrapped = Add-OrgAssert -Task $task -Resolution $resolution

            $wrapped.name | Should-Be $task.name
        }

        It 'puts the assert before the task in the block' {
            $task = [ordered] @{ 'name' = 'V-100 | MEDIUM | Maximum password age' }
            $resolution = [pscustomobject] @{ Assert = New-Assert }

            $wrapped = Add-OrgAssert -Task $task -Resolution $resolution

            $wrapped.block.Count | Should-Be 2
            $wrapped.block[0] | Should-Be $resolution.Assert
            $wrapped.block[1] | Should-Be $task
        }

        # The wrapping block is what the severity file toggles, so the conditional has to move
        # from the inner task onto it rather than staying behind on a task nobody sees directly.
        It 'carries the task''s when onto the wrapping block' {
            $task = [ordered] @{ 'name' = 'V-100 | MEDIUM | Maximum password age'; 'when' = 'stig_server_2022_100_when' }
            $resolution = [pscustomobject] @{ Assert = New-Assert }

            $wrapped = Add-OrgAssert -Task $task -Resolution $resolution

            $wrapped.when | Should-Be 'stig_server_2022_100_when'
        }

        It 'adds no when key when the task carries none' {
            $task = [ordered] @{ 'name' = 'V-100 | MEDIUM | Maximum password age' }
            $resolution = [pscustomobject] @{ Assert = New-Assert }

            $wrapped = Add-OrgAssert -Task $task -Resolution $resolution

            $wrapped.Contains('when') | Should-BeFalse
        }
    }
}
