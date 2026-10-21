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

    # Windows resolves a service account only under NT SERVICE (issue #144).
    Context 'an entry naming a service account' {

        It 'qualifies <Principal> as <Expected>' -ForEach @(
            @{ Principal = 'TrustedInstaller'; Expected = 'NT SERVICE\TrustedInstaller' }
            @{ Principal = 'Eventlog'; Expected = 'NT SERVICE\EventLog' }
            @{ Principal = 'NT SERVICE\TrustedInstaller'; Expected = 'NT SERVICE\TrustedInstaller' }
            @{ Principal = 'Administrators'; Expected = 'Administrators' }
        ) {
            $rule = New-PermissionRule -Entries @(
                [pscustomobject] @{ Principal = $Principal; Rights = 'FullControl'; Type = 'Allow'; Inheritance = 'This folder only' }
            )

            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule $rule -StigName 'WindowsServer-2022-MS').Task

            $task.block[0].'ansible.windows.win_acl'.user | Should-Be $Expected
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

    # SECURITY and SAM admit only SYSTEM to read them, but Administrators to rewrite their DACL.
    # win_acl asks for more than that, and runas to SYSTEM needs the Secondary Logon service a
    # client STIG disables, so the entry is set by a script opening the key for the DACL alone.
    # See #147, #200 and docs/adr/0023.
    Context 'a registry key only SYSTEM can read' {

        BeforeAll {
            function Get-SystemKeyTask {
                param ($Path, $Entries)

                $rule = New-PermissionRule -Path $Path -Entries $Entries
                $rule.DscResource = 'RegistryAccessEntry'
                (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' -Rule $rule -StigName 'WindowsServer-2025-MS').Task
            }
        }

        It 'sets the DACL of HKLM:\<Key> by script for <Path>' -ForEach @(
            @{ Path = 'HKLM:\SECURITY'; Key = 'SECURITY' }
            @{ Path = 'HKLM:\security\Policy'; Key = 'security\Policy' }
            @{ Path = 'HKLM:\SAM\SAM'; Key = 'SAM\SAM' }
            @{ Path = 'HKEY_LOCAL_MACHINE\SECURITY'; Key = 'SECURITY' }
        ) {
            $task = Get-SystemKeyTask -Path $Path

            $task.block[0].Contains('ansible.windows.win_acl') | Should-BeFalse
            $task.block[0].'ansible.windows.win_powershell'.parameters.Key | Should-Be $Key
        }

        It 'never switches to SYSTEM, which needs the Secondary Logon service' {
            $task = Get-SystemKeyTask -Path 'HKLM:\SECURITY'

            $task.block[0].Contains('become') | Should-BeFalse
            $task.block[0].Contains('become_user') | Should-BeFalse
        }

        It 'hands the script the entry win_acl would have set' {
            $parameters = (Get-SystemKeyTask -Path 'HKLM:\SECURITY' -Entries @(
                    [pscustomobject] @{ Principal = 'SYSTEM'; Rights = 'FullControl'; Type = ''; Inheritance = 'This key and subkeys' }
                )).block[0].'ansible.windows.win_powershell'.parameters

            $parameters.Identity | Should-Be 'SYSTEM'
            $parameters.Rights | Should-Be 'FullControl'
            $parameters.Type | Should-Be 'Allow'
            $parameters.Inheritance | Should-Be 'ContainerInherit'
            $parameters.Propagation | Should-Be 'None'
        }

        It 'opens the key for READ_CONTROL and WRITE_DAC alone' {
            $script = (Get-SystemKeyTask -Path 'HKLM:\SECURITY').block[0].'ansible.windows.win_powershell'.script

            $script | Should-BeLikeString '*RegistryRights] "ReadPermissions, ChangePermissions"*'
            $script | Should-BeLikeString '*OpenSubKey($Key, *, $access)*'
        }

        # win_powershell runs a script under --check only when it supports ShouldProcess.
        It 'reports a change and writes only when ShouldProcess allows' {
            $script = (Get-SystemKeyTask -Path 'HKLM:\SECURITY').block[0].'ansible.windows.win_powershell'.script

            $script | Should-BeLikeString '`[CmdletBinding(SupportsShouldProcess)`]*'
            $script | Should-BeLikeString '*$Ansible.Changed = $acl.Sddl -ne $before*'
            $script | Should-BeLikeString '*$PSCmdlet.ShouldProcess(*)) { $handle.SetAccessControl($acl) }*'
        }

        # The script is fixed text the entry is handed to, so it has to parse as PowerShell.
        It 'emits a script that parses' {
            $script = (Get-SystemKeyTask -Path 'HKLM:\SECURITY').block[0].'ansible.windows.win_powershell'.script
            $errors = $null

            $null = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref] $null, [ref] $errors)

            @($errors).Count | Should-Be 0
        }

        It 'leaves <Path> to win_acl' -ForEach @(
            @{ Path = 'HKLM:\SOFTWARE\Microsoft' }
            @{ Path = 'HKLM:\SECURITYX' }
            @{ Path = '%SystemRoot%\System32\config' }
        ) {
            $task = Get-SystemKeyTask -Path $Path

            $task.block[0].Contains('ansible.windows.win_acl') | Should-BeTrue
            $task.block[0].Contains('become') | Should-BeFalse
        }
    }

    # win_acl takes a path literally, so a wildcard has to be expanded on the target (issue #173).
    Context 'a path ending in a wildcard' {

        BeforeAll {
            $script:rule = New-PermissionRule -Id 'V-138' -Path '%windir%\NTDS\*.*'
            $script:block = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule $script:rule -StigName 'WindowsServer-2025-DC').Task.block
        }

        It 'finds the files in the directory first' {
            $find = $script:block[0].'ansible.windows.win_find'

            $find.paths | Should-Be "{{ stig_server_2025_env['windir'] }}\NTDS"
            $find.patterns | Should-BeCollection @('*.*')
            $find.file_type | Should-Be 'file'
            $script:block[0].register | Should-Be 'stig_server_2025_138_files'
        }

        It 'applies each entry to every file found' {
            $script:block[1].'ansible.windows.win_acl'.path | Should-Be '{{ item.path }}'
            $script:block[1].loop | Should-Be '{{ stig_server_2025_138_files.files }}'
        }

        It 'leaves a path with no wildcard to a single win_acl task' {
            $task = (Invoke-Generator -Generator 'Build-AnsiblePermissionTask' `
                -Rule (New-PermissionRule) -StigName 'WindowsServer-2025-DC').Task

            $task.block.Count | Should-Be 1
            $task.block[0].Contains('loop') | Should-BeFalse
        }
    }

    # RuleCorrection.psd1 can remove every entry a rule had, as it does V-278139's '(RX)'.
    # See docs/adr/0020.
    Context 'a rule left with no entry' {

        It 'builds nothing' {
            $rule = New-PermissionRule
            $rule.AccessControlEntry = [pscustomobject] @{ Entry = $null }

            Invoke-Generator -Generator 'Build-AnsiblePermissionTask' -Rule $rule -StigName 'WindowsServer-2025-DC' |
                Should-BeNull
        }
    }
}