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

    # A STIG with no rules of a given severity must not leave an empty cat file behind for
    # tasks/main.yml to import.
    Context 'entries with nothing to write' {

        It 'skips an entry whose value is <Reason>' -ForEach @(
            @{ Reason = 'null'; Value = $null }
            @{ Reason = 'an empty collection'; Value = @() }
        ) {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ nothing_to_write = $Value })

            Join-Path $TestDrive 'nothing_to_write.yml' | Should -Not -Exist
        }

        It 'still writes the entries that do have content' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{
                empty_one = @()
                populated_one = 'content'
            })

            Join-Path $TestDrive 'empty_one.yml' | Should -Not -Exist
            Join-Path $TestDrive 'populated_one.yml' | Should -Exist
        }
    }

    Context 'encoding' {

        It 'writes utf8 so STIG prose with non-ascii characters survives' {
            Save-File -OutputPath $TestDrive -Content ([ordered] @{ notice = 'consent to monitoring — see policy' })

            Get-Content -Path (Join-Path $TestDrive 'notice.yml') -Encoding utf8 |
                Should-BeLikeString '*see policy*'
        }
    }
}
