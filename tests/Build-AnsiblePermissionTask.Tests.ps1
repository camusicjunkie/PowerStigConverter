#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-PermissionRule {
        param ($Id = 'V-190', $Path = '%SystemRoot%\System32\config', $Entries)

        if (-not $Entries) {
            $Entries = @(
                [pscustomobject] @{
                    Principal = 'Administrators'
                    Rights = 'FullControl'
                    Type = 'Allow'
                    Inheritance = 'This folder subfolders and files'
                }
            )
        }

        [pscustomobject] @{
            Id = $Id
            Severity = 'high'
            DuplicateOf = ''
            Path = $Path
            DscResource = 'NTFSAccessEntry'
            AccessControlEntry = [pscustomobject] @{ Entry = $Entries }
            OrganizationValueRequired = $false
        }
    }
}

# Every access control entry on the rule becomes its own task inside one block, so this rule type
# always groups even when the id carries no sub-rule suffix.
Describe 'Build-AnsiblePermissionTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsiblePermissionTask' `
        -Module 'ansible.windows.win_acl' `
        -Factory { New-PermissionRule }

    Context 'the task it builds' {

        It 'sets the principal and rights the entry names' {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $acl = $task.block[0].'ansible.windows.win_acl'
            $acl.user | Should-Be 'Administrators'
            $acl.rights | Should-Be 'FullControl'
        }

        It 'translates the inheritance phrase into the flags win_acl takes' {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $acl = $task.block[0].'ansible.windows.win_acl'
            $acl.inherit | Should-Be 'ContainerInherit, ObjectInherit'
            $acl.propagation | Should-Be 'None'
        }

        It 'gives every access control entry its own task in the block' {
            $rule = New-PermissionRule -Entries @(
                [pscustomobject] @{ Principal = 'Administrators'; Rights = 'FullControl'; Type = 'Allow'; Inheritance = 'This folder only' }
                [pscustomobject] @{ Principal = 'Users'; Rights = 'ReadAndExecute'; Type = 'Allow'; Inheritance = 'This folder only' }
            )

            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule $rule -StigName 'WindowsServer-2022-MS').Task

            @($task.block).Count | Should-Be 2
            $task.block.'ansible.windows.win_acl'.user | Should-BeCollection @('Administrators', 'Users')
        }
    }

    # A STIG that does not say otherwise is granting, not denying.
    Context 'an entry that does not say whether it allows or denies' {

        It 'defaults the type to Allow' {
            $rule = New-PermissionRule -Entries @(
                [pscustomobject] @{ Principal = 'Users'; Rights = 'ReadAndExecute'; Type = ''; Inheritance = 'This folder only' }
            )

            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule $rule -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.type | Should-Be 'Allow'
        }
    }

    # Why the raw path rather than the expanded one: see the generator's help.
    Context 'a path holding an environment variable' {

        It 'sends it exactly as the STIG wrote it' {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.path | Should-Be '%SystemRoot%\System32\config'
        }

        It 'names the task for the same path, so the role reads the way it runs' {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-BeLikeString '*%SystemRoot%\System32\config'
        }

        # The whole point: the same rule converts to the same task wherever it is converted.
        It 'does not consult the converting machine' {
            Mock -ModuleName PowerStigConverter -CommandName Test-Path -MockWith {
                throw 'the generator must not ask the filesystem'
            }

            # Proves the mock is live, so a case that stops reaching the generator fails here
            # rather than passing on an assertion that can no longer be broken.
            InModuleScope -ModuleName PowerStigConverter { { Test-Path 'C:\' } | Should-Throw }

            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.path | Should-Be '%SystemRoot%\System32\config'
        }
    }
}
