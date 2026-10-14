#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Save-File {
        param ($Content, $OutputPath)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Content = $Content; OutputPath = $OutputPath } {
            param ($Content, $OutputPath)
            Save-AnsibleRoleFile -Content $Content -OutputPath $OutputPath
        }
    }
}

Describe 'Save-AnsibleRoleFile' {

    Context 'writing the generated files' {

        It 'writes each entry as a yml file named for its key' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{
                cat1 = 'high severity content'
                cat2 = 'medium severity content'
            })

            Join-Path $TestDrive 'cat1.yml' | Should -Exist
            Join-Path $TestDrive 'cat2.yml' | Should -Exist
        }

        It 'writes the content it was given' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ cat3 = 'low severity content' })

            Get-Content -Path (Join-Path $TestDrive 'cat3.yml') | Should-Be 'low severity content'
        }

        It 'writes a multi-line entry as one line per element' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{
                main_default_org = @('first: true', 'second: true', 'third: true')
            })

            Get-Content -Path (Join-Path $TestDrive 'main_default_org.yml') |
                Should-BeCollection @('first: true', 'second: true', 'third: true')
        }
    }

    # New-AnsiblePlaybook is documented as safe to re-run: the generated files are replaced
    # every time rather than appended to.
    Context 're-running over an existing role' {

        It 'replaces the previous content instead of appending to it' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ cat1 = 'from the first run' })
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ cat1 = 'from the second run' })

            Get-Content -Path (Join-Path $TestDrive 'cat1.yml') | Should-Be 'from the second run'
        }
    }

    # An entry with no content is an exporter bug; skipping it left a previous run's file on disk
    # (#131), so it fails the conversion instead (#135).
    Context 'entries with nothing to write' {

        It 'throws naming the file when an entry''s value is <Reason>' -ForEach @(
            @{ Reason = 'null'; Value = $null }
            @{ Reason = 'an empty collection'; Value = @() }
        ) {
            { Save-File -OutputPath $TestDrive -Content ([ordered] @{ nothing_to_write = $Value }) } |
                Should -Throw -ExpectedMessage '*nothing_to_write*'
        }

        It 'writes nothing for any entry when one is empty' {
            { Save-File -OutputPath $TestDrive -Content ([ordered] @{
                populated_one = 'content'
                empty_one = @()
            }) } | Should -Throw

            Join-Path $TestDrive 'populated_one.yml' | Should -Not -Exist
            Join-Path $TestDrive 'empty_one.yml' | Should -Not -Exist
        }

        It 'leaves a file from an earlier run alone' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ stale = 'from the first run' })
            { Save-File -OutputPath $TestDrive -Content ([ordered] @{ stale = $null }) } | Should -Throw

            Get-Content -Path (Join-Path $TestDrive 'stale.yml') | Should-Be 'from the first run'
        }
    }

    Context 'encoding' {

        It 'writes utf8 so STIG prose with non-ascii characters survives' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ notice = 'consent to monitoring — see policy' })

            Get-Content -Path (Join-Path $TestDrive 'notice.yml') -Encoding utf8 |
                Should-BeLikeString '*see policy*'
        }

        # Set-Content -Encoding utf8 means two different things: 5.1 writes a BOM and 7 does not,
        # so the same STIG converted on two machines produced two different files. Asserted on the
        # bytes, because Get-Content hides the BOM on both engines.
        It 'writes no byte order mark, so both engines produce the same file' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ no_bom = 'first: true' })

            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $TestDrive 'no_bom.yml'))
            # 0xEF 0xBB 0xBF is the BOM; the file must open on the content's own first byte.
            $bytes[0] | Should-Be ([byte][char] 'f')
        }
    }
}
