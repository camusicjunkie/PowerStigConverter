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
Describe 'New-AnsiblePermissionTask' {

    # The generator asks the filesystem whether the expanded path exists; mocked so the result
    # does not depend on the machine running the suite. See #8.
    BeforeAll {
        InModuleScope -ModuleName PowerStigConverter { Mock Test-Path { $true } }
    }

    Add-GeneratorContractTests -Generator 'New-AnsiblePermissionTask' `
        -Module 'ansible.windows.win_acl' `
        -Factory { New-PermissionRule }

    Context 'the task it builds' {

        It 'sets the principal and rights the entry names' {
            $task = (Invoke-Generator -Generator 'New-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $acl = $task.block[0].'ansible.windows.win_acl'
            $acl.user | Should-Be 'Administrators'
            $acl.rights | Should-Be 'FullControl'
        }

        It 'translates the inheritance phrase into the flags win_acl takes' {
            $task = (Invoke-Generator -Generator 'New-AnsiblePermissionTask' `
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

            $task = (Invoke-Generator -Generator 'New-AnsiblePermissionTask' `
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

            $task = (Invoke-Generator -Generator 'New-AnsiblePermissionTask' `
                -Rule $rule -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.type | Should-Be 'Allow'
        }
    }

    # Both branches of the Test-Path decision, so the behaviour is pinned before it is changed.
    Context 'expanding an environment variable in the path' {

        It 'sends the expanded path when it exists on the converting machine' {
            InModuleScope -ModuleName PowerStigConverter { Mock Test-Path { $true } }

            $task = (Invoke-Generator -Generator 'New-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.path |
                Should-Be ([System.Environment]::ExpandEnvironmentVariables('%SystemRoot%\System32\config'))
        }

        It 'falls back to the unexpanded path when it does not' {
            InModuleScope -ModuleName PowerStigConverter { Mock Test-Path { $false } }

            $task = (Invoke-Generator -Generator 'New-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.path | Should-Be '%SystemRoot%\System32\config'
        }
    }
}
