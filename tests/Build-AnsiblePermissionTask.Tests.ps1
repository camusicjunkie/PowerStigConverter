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

    # win_acl takes the path literally, so a variable is resolved on the target from the role's
    # env fact, keyed by lowercased name because Windows ignores the case STIGs vary. See docs/adr/0017.
    Context 'a path holding an environment variable' {

        It 'reads <Path> from the target environment as <Expected>' -ForEach @(
            @{ Path = '%SystemRoot%\System32\config'; Expected = "{{ stig_server_2022_env['systemroot'] }}\System32\config" }
            @{ Path = '%Windir%\System32\eventvwr.exe'; Expected = "{{ stig_server_2022_env['windir'] }}\System32\eventvwr.exe" }
            @{ Path = '%ProgramFiles(x86)%'; Expected = "{{ stig_server_2022_env['programfiles(x86)'] }}" }
            @{ Path = 'C:\Windows\System32'; Expected = 'C:\Windows\System32' }
        ) {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule -Path $Path) -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.path | Should-Be $Expected
        }

        It 'names the task for the path as the STIG wrote it' {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-BeLikeString '*%SystemRoot%\System32\config'
        }

        # That the generator never asks this machine about the path is item 8 of the contract,
        # which every generator test now runs.
    }
}
