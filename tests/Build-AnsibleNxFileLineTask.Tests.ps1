#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-NxFileLineRule {
        param (
            $Id = 'V-257945',
            $Severity = 'medium',
            $FilePath = '/etc/chrony.conf',
            $ContainsLine = 'maxpoll 16',
            $DoesNotContainPattern = '#\s*maxpoll\s*16',
            $OrganizationValueRequired = $false
        )

        [pscustomobject] @{
            Id = $Id
            Severity = $Severity
            DuplicateOf = ''
            FilePath = $FilePath
            ContainsLine = $ContainsLine
            DoesNotContainPattern = $DoesNotContainPattern
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function Get-NxFileLineItem {
        param ($Rule, $OrganizationalSetting = @{})

        Invoke-Generator -Generator 'Build-AnsibleNxFileLineTask' -Rule $Rule `
            -StigName 'OracleLinux-8' -OrganizationalSetting $OrganizationalSetting
    }

    function Get-NxFileLineTask {
        param ($Rule, $OrganizationalSetting = @{})

        (Get-NxFileLineItem -Rule $Rule -OrganizationalSetting $OrganizationalSetting).Task
    }

    # The warning is written from inside the module, so it is read off the warning stream rather
    # than through a mock.
    function Get-NxFileLineWarning {
        param ($Rule)

        @((Invoke-Generator -Generator 'Build-AnsibleNxFileLineTask' -Rule $Rule -StigName 'OracleLinux-8') 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    }
}

# 420 in-scope rules of this map's largest generator by far. One lineinfile per rule, or copy for
# the one rule whose ContainsLine cannot fit lineinfile's single-line shape. See ADR 0009.
Describe 'Build-AnsibleNxFileLineTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleNxFileLineTask' `
        -Module 'ansible.builtin.lineinfile' `
        -StigName 'OracleLinux-8' `
        -Factory { New-NxFileLineRule }

    Context 'the task it builds' {

        It 'points lineinfile at the file and line the rule names' {
            $lineinfile = (Get-NxFileLineTask -Rule (New-NxFileLineRule)).'ansible.builtin.lineinfile'

            $lineinfile.path | Should-Be '/etc/chrony.conf'
            $lineinfile.line | Should-Be 'maxpoll 16'
        }

        It 'ports DoesNotContainPattern to regexp verbatim' {
            $lineinfile = (Get-NxFileLineTask -Rule (New-NxFileLineRule)).'ansible.builtin.lineinfile'

            $lineinfile.regexp | Should-Be '#\s*maxpoll\s*16'
        }

        It 'escalates' {
            $task = Get-NxFileLineTask -Rule (New-NxFileLineRule)

            $task.become | Should-BeTrue
        }

        It 'inlines the line into the detail, unabridged' {
            $task = Get-NxFileLineTask -Rule (New-NxFileLineRule -Id 'V-257945' -Severity 'medium')

            $task.name | Should-Be 'V-257945 | MEDIUM | Ensure chrony.conf contains "maxpoll 16"'
        }
    }

    # ADR 0009's skip-and-warn guard: PowerStig data the generator cannot turn into a working
    # task produces no task at all, with a warning saying why.
    Context 'a rule PowerStig could not have meant as a line to write' {

        It 'skips a directory FilePath rather than writing to it' {
            $rule = New-NxFileLineRule -FilePath '/etc/modprobe.d/'

            @(Get-NxFileLineItem -Rule $rule 3>$null).Count | Should-Be 0
        }

        It 'warns why it skipped a directory FilePath' {
            $warning = Get-NxFileLineWarning -Rule (New-NxFileLineRule -Id 'V-1' -FilePath '/etc/modprobe.d/')

            $warning.Message | Should-BeLikeString '*V-1*directory*'
        }

        It 'skips a DoesNotContainPattern that compiles in no regex engine' {
            $rule = New-NxFileLineRule -DoesNotContainPattern '\s**'

            @(Get-NxFileLineItem -Rule $rule 3>$null).Count | Should-Be 0
        }

        It 'skips a ContainsLine carrying a non-ASCII character' {
            $rule = New-NxFileLineRule -ContainsLine "line with a non-breaking space`u{00A0}here"

            @(Get-NxFileLineItem -Rule $rule 3>$null).Count | Should-Be 0
        }

        It 'skips a rule id known to carry check-text prose instead of a line' {
            $rule = New-NxFileLineRule -Id 'V-248535'

            @(Get-NxFileLineItem -Rule $rule 3>$null).Count | Should-Be 0
        }

        It 'does not skip the DoD banner rule, despite matching the same prose keywords' {
            $rule = New-NxFileLineRule -Id 'V-257779' -ContainsLine "following conditions`nmore text"

            @(Get-NxFileLineItem -Rule $rule 3>$null).Count | Should-Be 1
        }
    }

    Context 'a multi-line ContainsLine' {

        It 'emits copy instead of lineinfile, keyed on the file content rather than a pattern' {
            $rule = New-NxFileLineRule -Id 'V-257779' -FilePath '/etc/issue' `
                -ContainsLine "line one`nline two" -DoesNotContainPattern ''

            $task = Get-NxFileLineTask -Rule $rule
            $copy = $task.'ansible.builtin.copy'

            $copy | Should-NotBeNull
            $task.Contains('ansible.builtin.lineinfile') | Should-BeFalse
            $copy.dest | Should-Be '/etc/issue'
            $copy.content | Should-Be "line one`nline two"
        }

        It 'gives the task generic wording rather than inlining the banner' {
            $rule = New-NxFileLineRule -Id 'V-257779' -FilePath '/etc/issue' `
                -ContainsLine "line one`nline two" -DoesNotContainPattern ''

            $task = Get-NxFileLineTask -Rule $rule

            $task.name | Should-Be 'V-257779 | MEDIUM | Ensure issue contains the required banner text'
        }
    }

    # Sub-rules collapse into one block under one toggle; a meaningful fraction touch more than
    # one file for the same requirement, so the block's name has to say so.
    Context 'a sub-rule group' {

        BeforeAll {
            function New-GroupRuleSet {
                param ($BaseId, $FilePathA, $FilePathB)

                @(
                    [pscustomobject] @{
                        Id = '{0}.a' -f $BaseId; Severity = 'medium'; DuplicateOf = ''
                        FilePath = $FilePathA; ContainsLine = 'blacklist bluetooth'
                        DoesNotContainPattern = '#\s*blacklist\s*bluetooth'; OrganizationValueRequired = $false
                    }
                    [pscustomobject] @{
                        Id = '{0}.b' -f $BaseId; Severity = 'medium'; DuplicateOf = ''
                        FilePath = $FilePathB; ContainsLine = 'blacklist bluetooth'
                        DoesNotContainPattern = '#\s*blacklist\s*bluetooth'; OrganizationValueRequired = $false
                    }
                )
            }
        }

        It 'nests both sub-rules in one block' {
            $grouped = InModuleScope -ModuleName PowerStigConverter -Parameters @{
                Rules = New-GroupRuleSet -BaseId 'V-248828' -FilePathA '/bin/false' -FilePathB '/etc/modprobe.d/bluetooth.conf'
            } {
                param ($Rules)
                $Rules | ConvertTo-AnsibleTask -RuleType 'nxFileLine' -StigName 'OracleLinux-8'
            }

            @($grouped).Count | Should-Be 1
            @($grouped.Task.block).Count | Should-Be 2
        }

        It 'names the block for the distinct leaves both sub-rules touch, in order of appearance' {
            $grouped = InModuleScope -ModuleName PowerStigConverter -Parameters @{
                Rules = New-GroupRuleSet -BaseId 'V-248828' -FilePathA '/bin/false' -FilePathB '/etc/modprobe.d/bluetooth.conf'
            } {
                param ($Rules)
                $Rules | ConvertTo-AnsibleTask -RuleType 'nxFileLine' -StigName 'OracleLinux-8'
            }

            $grouped.Task.name | Should-Be 'V-248828 | MEDIUM | false, bluetooth.conf'
        }

        It 'lists a leaf once when every sub-rule shares it' {
            $grouped = InModuleScope -ModuleName PowerStigConverter -Parameters @{
                Rules = New-GroupRuleSet -BaseId 'V-171' -FilePathA '/etc/audit/rules.d/audit.rules' -FilePathB '/etc/audit/rules.d/audit.rules'
            } {
                param ($Rules)
                $Rules | ConvertTo-AnsibleTask -RuleType 'nxFileLine' -StigName 'OracleLinux-8'
            }

            $grouped.Task.name | Should-Be 'V-171 | MEDIUM | audit.rules'
        }
    }

    Context 'a value the organization decides' {

        It 'interpolates a variable for the line and another for its commented-out form' {
            $rule = New-NxFileLineRule -ContainsLine '' -DoesNotContainPattern '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting ('<OrganizationalSetting id="{0}" ContainsLine="maxpoll 16" DoesNotContainPattern="#\s*maxpoll\s*16" />' -f 'V-257945')

            $lineinfile = (Get-NxFileLineTask -Rule $rule -OrganizationalSetting $orgSetting).'ansible.builtin.lineinfile'

            $lineinfile.line | Should-Be '{{ stig_oraclelinux_8_257945_containsline }}'
            $lineinfile.regexp | Should-Be '{{ stig_oraclelinux_8_257945_doesnotcontainpattern }}'
        }

        It 'guards both unanswered variables with an assert' {
            $rule = New-NxFileLineRule -ContainsLine '' -DoesNotContainPattern '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-257945" ContainsLine="" DoesNotContainPattern="" />'

            $task = Get-NxFileLineTask -Rule $rule -OrganizationalSetting $orgSetting

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }
}
