#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Resolve-StigPath {
        param ($Path)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Path = $Path } {
            param ($Path)
            Resolve-PowerStigPath -Path $Path
        }
    }

    function Resolve-OutputPath {
        param ($Path)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Path = $Path } {
            param ($Path)
            Resolve-AnsibleOutputPath -Path $Path
        }
    }
}

Describe 'Resolve-PowerStigPath' {

    # Decides where the PowerStig data lives. Copy-PowerStigFile writes there and
    # Get-PowerStigFile reads from there, so the two have to agree on the default.
    Context 'no path given' {

        It 'defaults to the PowerStig folder under LOCALAPPDATA' {
            Resolve-StigPath | Should-Be (Join-Path $env:LOCALAPPDATA 'PowerStig')
        }

        It 'defaults the same way for <Reason>' -ForEach @(
            @{ Reason = 'an empty string'; Path = '' }
            @{ Reason = 'whitespace'; Path = '   ' }
        ) {
            Resolve-StigPath -Path $Path | Should-Be (Join-Path $env:LOCALAPPDATA 'PowerStig')
        }
    }

    # Copy-PowerStigFile creates the directory, so resolution must not require it to be there
    # already - Resolve-Path would throw on a target that does not exist yet.
    Context 'a path that does not exist yet' {

        It 'resolves a relative path against the current location without requiring a target' {
            Push-Location -Path $TestDrive
            try {
                Resolve-StigPath -Path './not-created-yet' | Should-Be (Join-Path $TestDrive 'not-created-yet')
            }
            finally {
                Pop-Location
            }
        }

        It 'does not create the directory as a side effect of resolving it' {
            Push-Location -Path $TestDrive
            try {
                $resolved = Resolve-StigPath -Path './still-not-created'
                $resolved | Should -Not -Exist
            }
            finally {
                Pop-Location
            }
        }
    }

    Context 'an absolute path' {

        It 'returns it unchanged' {
            $absolute = Join-Path $TestDrive 'stigs'

            Resolve-StigPath -Path $absolute | Should-Be $absolute
        }
    }
}

Describe 'Resolve-AnsibleOutputPath' {

    # Decides where the role directory is created. Unlike the STIG data path, this one has to
    # exist by the time plaster runs, so resolving it also creates it.
    Context 'no path given' {

        It 'defaults to the current location, so a role lands where the user is standing' {
            Push-Location -Path $TestDrive
            try {
                Resolve-OutputPath | Should-Be $TestDrive
            }
            finally {
                Pop-Location
            }
        }
    }

    Context 'a path that does not exist yet' {

        It 'creates the directory, because the README promises it does not have to exist' {
            $target = Join-Path $TestDrive 'roles'

            $resolved = Resolve-OutputPath -Path $target

            $resolved | Should -Exist
            $resolved | Should-Be $target
        }

        It 'creates intermediate directories too' {
            $target = Join-Path $TestDrive 'deep' | Join-Path -ChildPath 'nested' | Join-Path -ChildPath 'roles'

            Resolve-OutputPath -Path $target | Should -Exist
        }

        It 'resolves a relative path against the current location' {
            Push-Location -Path $TestDrive
            try {
                Resolve-OutputPath -Path './relative-roles' | Should-Be (Join-Path $TestDrive 'relative-roles')
            }
            finally {
                Pop-Location
            }
        }
    }

    Context 'a path that already exists' {

        It 'leaves the existing directory and its contents alone' {
            $target = Join-Path $TestDrive 'existing'
            $null = New-Item -Path $target -ItemType Directory -Force
            Set-Content -Path (Join-Path $target 'keep-me.txt') -Value 'still here'

            $null = Resolve-OutputPath -Path $target

            Join-Path $target 'keep-me.txt' | Should -Exist
        }
    }
}
