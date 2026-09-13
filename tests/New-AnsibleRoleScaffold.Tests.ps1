#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-Scaffold {
        param ($Path, $RoleName, $StigName)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Path = $Path; RoleName = $RoleName; StigName = $StigName
        } {
            param ($Path, $RoleName, $StigName)
            New-AnsibleRoleScaffold -Path $Path -RoleName $RoleName -StigName $StigName 6>$null
        }
    }
}

Describe 'New-AnsibleRoleScaffold' {

    Context 'laying out a new role' {

        BeforeAll {
            $script:root = Join-Path $TestDrive 'new'
            $null = New-Item -Path $root -ItemType Directory -Force
            $script:scaffold = New-Scaffold -Path $root -RoleName 'my_role' -StigName 'WindowsServer-2022-MS'
        }

        It 'creates the role directory under the path it was given' {
            $scaffold.Path | Should-Be (Join-Path $root 'my_role')
            $scaffold.Path | Should -Exist
        }

        It 'reports where the generated files go' {
            $scaffold.TaskPath | Should-Be (Join-Path $scaffold.Path 'tasks')
            $scaffold.DefaultPath | Should-Be (Join-Path $scaffold.Path 'defaults' | Join-Path -ChildPath 'main')
            $scaffold.HandlerPath | Should-Be (Join-Path $scaffold.Path 'handlers')
        }

        It 'creates the hand-editable <RelativePath>' -ForEach @(
            @{ RelativePath = 'tasks/main.yml' }
            @{ RelativePath = 'defaults/main/main.yml' }
            @{ RelativePath = 'vars/main.yml' }
            @{ RelativePath = 'handlers/main.yml' }
        ) {
            Join-Path $scaffold.Path $RelativePath | Should -Exist
        }

        It 'creates the directories the generated files are written into' {
            $scaffold.TaskPath | Should -Exist
            $scaffold.DefaultPath | Should -Exist
            $scaffold.HandlerPath | Should -Exist
        }

        # The hand-editable one is written once and never again, so the generated handlers go in
        # a file of their own that it imports.
        It 'has the hand-editable handler file import the generated one' {
            Join-Path $scaffold.Path 'handlers/main.yml' | Should -FileContentMatch 'import_tasks: generated.yml'
        }
    }

    # The scaffolding and the generated files have to agree on variable names, so the template
    # is handed the same prefix the generators derive.
    Context 'naming things from the STIG' {

        It 'uses the prefix derived from the STIG throughout the scaffolding' {
            $root = Join-Path $TestDrive 'named'
            $null = New-Item -Path $root -ItemType Directory -Force
            $scaffold = New-Scaffold -Path $root -RoleName 'named_role' -StigName 'WindowsClient-11'

            $main = Get-Content -Path (Join-Path $scaffold.Path 'tasks/main.yml') -Raw
            $defaults = Get-Content -Path (Join-Path $scaffold.Path 'defaults/main/main.yml') -Raw

            $main | Should-BeLikeString '*stig_client_11_cat1*'
            $defaults | Should-BeLikeString '*stig_client_11_server_core*'
        }

        It 'asserts the OS the STIG is for' {
            $root = Join-Path $TestDrive 'os'
            $null = New-Item -Path $root -ItemType Directory -Force
            $scaffold = New-Scaffold -Path $root -RoleName 'os_role' -StigName 'WindowsServer-2012R2-DC'

            Get-Content -Path (Join-Path $scaffold.Path 'tasks/main.yml') -Raw |
                Should-BeLikeString '*Microsoft Windows Server 2012 R2*'
        }
    }

    # Re-running New-AnsiblePlaybook must not discard edits to the four scaffolding files, so
    # the template is only ever run when the role is not already there.
    Context 'a role that already exists' {

        BeforeAll {
            $script:existingRoot = Join-Path $TestDrive 'existing'
            $null = New-Item -Path $existingRoot -ItemType Directory -Force
            $script:first = New-Scaffold -Path $existingRoot -RoleName 'again' -StigName 'WindowsServer-2022-MS'

            Set-Content -Path (Join-Path $first.Path 'vars/main.yml') -Value '# hand written'
            $script:second = New-Scaffold -Path $existingRoot -RoleName 'again' -StigName 'WindowsServer-2022-MS'
        }

        It 'leaves the existing scaffolding files untouched' {
            Get-Content -Path (Join-Path $first.Path 'vars/main.yml') -Raw |
                Should-BeLikeString '*hand written*'
        }

        It 'still reports the same paths, so the caller can carry on writing into them' {
            $second.Path | Should-Be $first.Path
            $second.TaskPath | Should-Be $first.TaskPath
            $second.DefaultPath | Should-Be $first.DefaultPath
        }
    }

    # A role whose directories were partly removed, or one that predates the defaults/main
    # layout, still has to end up with somewhere to write the generated files.
    Context 'a role missing the generated directories' {

        It 'recreates the directories without re-running the template' {
            $root = Join-Path $TestDrive 'partial'
            $null = New-Item -Path $root -ItemType Directory -Force
            $scaffold = New-Scaffold -Path $root -RoleName 'partial_role' -StigName 'WindowsServer-2022-MS'

            Set-Content -Path (Join-Path $scaffold.Path 'handlers/main.yml') -Value '# hand written'
            Remove-Item -Path $scaffold.TaskPath -Recurse -Force
            Remove-Item -Path $scaffold.DefaultPath -Recurse -Force

            $repaired = New-Scaffold -Path $root -RoleName 'partial_role' -StigName 'WindowsServer-2022-MS'

            $repaired.TaskPath | Should -Exist
            $repaired.DefaultPath | Should -Exist
            Get-Content -Path (Join-Path $scaffold.Path 'handlers/main.yml') -Raw |
                Should-BeLikeString '*hand written*'
        }
    }
}
