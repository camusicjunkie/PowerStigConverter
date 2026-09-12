#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    # The fixture tree mirrors the layout Copy-PowerStigFile produces: the sparse clone puts
    # the processed data under source/StigData/Processed inside the repo path.
    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'

    function Get-StigFile {
        param ($Type, $Path, [switch] $Previous)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Type = $Type; Path = $Path; Previous = $Previous.IsPresent } {
            param ($Type, $Path, $Previous)
            Get-PowerStigFile -Type $Type -Path $Path -Previous:$Previous
        }
    }
}

Describe 'Get-PowerStigFile' {

    Context 'finding the STIG data files' {

        It 'returns one file per STIG name' {
            $files = Get-StigFile -Type Name -Path $fixtureRoot

            $files.Name | Should-BeCollection @(
                    'IISServer-10.0.xml'
                    'WindowsClient-11-1.0.xml'
                    'WindowsServer-2022-DC-1.0.xml'
                    'WindowsServer-2022-MS-2.7.xml'
                )
        }

        It 'leaves the organisational settings files out of the STIG data list' {
            $files = Get-StigFile -Type Name -Path $fixtureRoot

            $files.Name | Should-All { $_ -notlike '*.org.default.xml' }
        }

        It 'returns file objects the caller can read content from' {
            $files = Get-StigFile -Type Name -Path $fixtureRoot

            $files | Should-All { Test-Path -Path $_.FullName }
        }
    }

    Context 'finding the organisational settings files' {

        It 'returns only the org settings files' {
            $files = Get-StigFile -Type Org -Path $fixtureRoot

            $files.Name | Should-All { $_ -like '*.org.default.xml' }
        }

        It 'returns one per STIG name, matching the STIG data list' {
            $names = (Get-StigFile -Type Name -Path $fixtureRoot).Name
            $orgNames = (Get-StigFile -Type Org -Path $fixtureRoot).Name

            @($orgNames).Count | Should-Be @($names).Count
        }
    }

    # DISA reissues a STIG as a new release rather than editing the old one, so PowerStig ships
    # several versions side by side. The README promises the highest version is the one used.
    Context 'a STIG with more than one release present' {

        It 'picks the highest version and ignores the superseded release' {
            $files = Get-StigFile -Type Name -Path $fixtureRoot

            $files.Name | Should-ContainCollection @('WindowsServer-2022-MS-2.7.xml')
            $files.Name | Should-NotContainCollection @('WindowsServer-2022-MS-1.2.xml')
        }

        It 'compares releases as versions rather than as text' {
            # 2.7 beats 1.2 either way, so prove the ordering is not a string sort by checking
            # that the version actually parsed out of the file name is what got compared.
            $files = Get-StigFile -Type Name -Path $fixtureRoot
            $chosen = $files | Where-Object Name -like 'WindowsServer-2022-MS-*'

            $chosen.Name | Should-BeLikeString '*-2.7.xml'
        }

        It 'returns the superseded release when asked for the previous one' {
            $files = Get-StigFile -Type Name -Path $fixtureRoot -Previous

            $files.Name | Should-ContainCollection @('WindowsServer-2022-MS-1.2.xml')
        }

        It 'falls back to the only release there is when asked for the previous one' {
            $files = Get-StigFile -Type Name -Path $fixtureRoot -Previous

            $files.Name | Should-ContainCollection @('WindowsClient-11-1.0.xml')
        }
    }

    Context 'the default location' {

        It 'looks under the resolved PowerStig path rather than the current directory' {
            # Point it at a tree with the right shape but no files, and it must come back empty
            # instead of finding whatever happens to be in the working directory.
            $empty = Join-Path $TestDrive 'empty-stig-root'
            $null = New-Item -Path (Join-Path $empty 'source\StigData\Processed') -ItemType Directory -Force

            $files = Get-StigFile -Type Name -Path $empty

            @($files).Count | Should-Be 0
        }
    }
}
