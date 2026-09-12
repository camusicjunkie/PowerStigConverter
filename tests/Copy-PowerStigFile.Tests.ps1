#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Copy-PowerStigFile' {

    # git is an external program at the edge of the module, so it is mocked here rather than
    # actually cloning Microsoft's repository. What is being checked is the command line this
    # function builds: a sparse clone of only the processed STIG data.
    Context 'fetching the PowerStig data' {

        BeforeAll {
            $script:target = Join-Path $TestDrive 'stigs'
        }

        BeforeEach {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith { }
        }

        It 'clones without checking anything out, so only the sparse paths are fetched' {
            Copy-PowerStigFile -Path $target

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 1 -ParameterFilter {
                $args -contains 'clone' -and $args -contains '--no-checkout'
            }
        }

        It 'clones the PowerStig repository into the path it was given' {
            Copy-PowerStigFile -Path $target

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 1 -ParameterFilter {
                $args -contains 'https://github.com/microsoft/PowerStig.git' -and $args -contains $target
            }
        }

        It 'limits the sparse checkout to the processed STIG data' {
            Copy-PowerStigFile -Path $target

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 1 -ParameterFilter {
                $args -contains 'sparse-checkout' -and $args -contains 'source/StigData/Processed'
            }
        }

        It 'checks the data out of the dev branch, which is where PowerStig publishes it' {
            Copy-PowerStigFile -Path $target

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 1 -ParameterFilter {
                $args -contains 'checkout' -and $args -contains 'origin/dev'
            }
        }

        It 'runs the two follow-up commands against the clone rather than the current directory' {
            Copy-PowerStigFile -Path $target

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 2 -ParameterFilter {
                $args -contains '-C' -and $args -contains $target
            }
        }
    }

    Context 'no path given' {

        BeforeEach {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith { }
        }

        It 'fetches into the default location New-AnsiblePlaybook reads from' {
            Copy-PowerStigFile

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 1 -ParameterFilter {
                $args -contains (Join-Path $env:LOCALAPPDATA 'PowerStig')
            }
        }
    }

    # git reports trouble by exit code rather than by throwing, so a failed clone used to be
    # followed by two commands run against a repository that was never created, and the whole
    # thing returned as if it had worked.
    Context 'a git command that fails' {

        It 'warns which step failed rather than returning as if it worked' {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith { $global:LASTEXITCODE = 128 }

            $warnings = Copy-PowerStigFile -Path (Join-Path $TestDrive 'failed') 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $warnings.Message | Should-BeLikeString '*clone*'
            $warnings.Message | Should-BeLikeString '*128*'
        }

        It 'stops rather than running the rest against a clone that is not there' {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith { $global:LASTEXITCODE = 128 }

            Copy-PowerStigFile -Path (Join-Path $TestDrive 'failed2') 3>$null

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Exactly -Times 1
        }

        # The failure the user is most likely to meet: fetching again into a path that already
        # holds a clone, which git refuses with the same silent 128.
        It 'stops at the step that failed rather than the first one' {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith {
                $global:LASTEXITCODE = if ($args -contains 'sparse-checkout') { 128 } else { 0 }
            }

            Copy-PowerStigFile -Path (Join-Path $TestDrive 'failed3') 3>$null

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Exactly -Times 2
            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Times 0 -ParameterFilter {
                $args -contains 'checkout' -and $args -contains 'origin/dev'
            }
        }
    }

    # A stale exit code from something the caller ran earlier must not read as this fetch failing.
    Context 'a non-zero exit code left over from an earlier command' {

        It 'still completes all three steps' {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith { }
            $global:LASTEXITCODE = 1

            Copy-PowerStigFile -Path (Join-Path $TestDrive 'stale') 3>$null

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Exactly -Times 3
        }
    }

    # The module cannot fetch anything without git, and the README lists it as a requirement.
    # A missing git has to be reported rather than throwing an unhandled error at the user.
    Context 'git not available' {

        It 'warns that git must be installed instead of failing the command' {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith {
                throw [System.Management.Automation.CommandNotFoundException]::new('git is not installed')
            }

            $warnings = Copy-PowerStigFile -Path (Join-Path $TestDrive 'nogit') 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $warnings.Message | Should-BeLikeString '*Git is not installed*'
        }

        It 'does not let the error escape to the caller' {
            Mock -ModuleName PowerStigConverter -CommandName git -MockWith {
                throw [System.Management.Automation.CommandNotFoundException]::new('git is not installed')
            }

            # An error escaping fails this case on the call itself. The count then says the clone
            # failing stops the checkout rather than carrying on against a repository that is
            # not there.
            Copy-PowerStigFile -Path (Join-Path $TestDrive 'nogit2') 3>$null

            Should-Invoke -ModuleName PowerStigConverter -CommandName git -Exactly -Times 1
        }
    }
}
