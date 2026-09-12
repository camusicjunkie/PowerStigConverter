#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    # Every test builds its own rule. The generators no longer write OrganizationValueRequired
    # back onto the rule they were handed - ADR-0003 deleted both write-backs, and the contract's
    # idempotency case now holds them to it - but a fresh rule per case still keeps a failure from
    # being an artefact of the case before it.
    function New-LoggingRule {
        param ($Id = 'V-300')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            OrganizationValueRequired = $false
            LogFlags = 'Date,Time,ClientIP'
            LogFormat = 'W3C'
            LogPeriod = 'Daily'
            LogTargetW3C = 'File,ETW'
            LogCustomFieldEntry = ''
        }
    }

    function New-LoggingTask {
        param ($Rule)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rule = $Rule } {
            param ($Rule)
            ($Rule | New-AnsibleIisLoggingTask -StigName 'IISServer-10.0').Task
        }
    }
}

Describe 'New-AnsibleIisLoggingTask' {

    Add-GeneratorContractTests -Generator 'New-AnsibleIisLoggingTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'IISServer-10.0' `
        -Factory { New-LoggingRule }

    # IIS logging is applied through the DSC resource rather than a native ansible module,
    # because there is no ansible module covering it.
    Context 'the task it builds' {

        It 'uses win_dsc with the IISLogging resource' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.Keys | Should-ContainCollection @('ansible.windows.win_dsc')
            $task.'ansible.windows.win_dsc'.resource_name | Should-Be 'IISLogging'
        }

        It 'points the resource at the log path variable the site fills in' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.'ansible.windows.win_dsc'.LogPath | Should-Be '{{ stig_iisserver_10_0_300_logpath }}'
        }

        It 'names the toggle for the rule id' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.when | Should-Be 'stig_iisserver_10_0_300_when'
        }
    }

    # Each of these comes off the resolved organization value. They are read by the names the
    # resolution reports, which are not all the names the STIG rule uses - reading the rule's
    # names instead yields null and the setting is silently dropped.
    Context 'carrying the logging settings through' {

        It 'carries the <Property> through unchanged' -ForEach @(
            @{ Property = 'LogFormat'; Expected = 'W3C' }
            @{ Property = 'LogPeriod'; Expected = 'Daily' }
        ) {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.'ansible.windows.win_dsc'.$Property | Should-Be $Expected
        }
    }

    Context 'settings the rule does not specify' {

        It 'leaves out a setting the rule has nothing for, rather than sending an empty one' {
            $sparse = [pscustomobject] @{
                Id = 'V-301'
                Severity = 'medium'
                DuplicateOf = ''
                OrganizationValueRequired = $false
                LogFlags = ''
                LogFormat = ''
                LogPeriod = ''
                LogTargetW3C = ''
                LogCustomFieldEntry = ''
            }

            $task = New-LoggingTask -Rule $sparse

            $task.'ansible.windows.win_dsc'.Keys | Should-NotContainCollection @('LogFlags')
            $task.'ansible.windows.win_dsc'.Keys | Should-NotContainCollection @('LogTargetW3C')
        }
    }

    # Item 6 of the contract. The DSC resource takes these two as lists, and PowerShell will
    # quietly unroll a one-element array back to a string on the way out of an if - which is how
    # a LogTargetW3C of just File came to be written as a scalar rather than a sequence.
    Context 'a value the task needs as a list' {

        It 'splits the log flags into a list' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.'ansible.windows.win_dsc'.LogFlags | Should-BeCollection @('Date', 'Time', 'ClientIP')
        }

        It 'splits the log target into a list' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.'ansible.windows.win_dsc'.LogTargetW3C | Should-BeCollection @('File', 'ETW')
        }

        It 'keeps a single <Property> a list rather than unrolling it to a string' -ForEach @(
            @{ Property = 'LogFlags'; Single = @{ LogFlags = 'Date' } }
            @{ Property = 'LogTargetW3C'; Single = @{ LogTargetW3C = 'File' } }
        ) {
            $rule = New-LoggingRule
            $rule.($Single.Keys | Select-Object -First 1) = $Single.Values | Select-Object -First 1

            $value = (New-LoggingTask -Rule $rule).'ansible.windows.win_dsc'.$Property

            $value -is [array] | Should-BeTrue
            @($value).Count | Should-Be 1
        }
    }

    # Item 7 of the contract. Every field the task consumes gets its own variable, so an operator
    # can answer one policy question without touching the others.
    Context 'a value the organization decides' {

        BeforeAll {
            $script:orgRule = New-LoggingRule
            $script:orgRule.OrganizationValueRequired = $true
            $script:answered = New-ContractOrgSetting ('<OrganizationalSetting id="V-300" LogFlags="Date,Time" ' +
                'LogFormat="W3C" LogPeriod="Daily" LogTargetW3C="File" />')
        }

        It 'interpolates a variable per field rather than inlining the values' {
            $dsc = (Invoke-Generator -Generator 'New-AnsibleIisLoggingTask' -Rule $orgRule `
                -StigName 'IISServer-10.0' -OrganizationalSetting $answered).Task.'ansible.windows.win_dsc'

            $dsc.LogFormat | Should-Be '{{ stig_iisserver_10_0_300_logformat }}'
            $dsc.LogTargetW3C | Should-Be '{{ stig_iisserver_10_0_300_logtargetw3c }}'
        }

        It 'guards an unanswered field with an assert naming that field' {
            $blank = New-ContractOrgSetting ('<OrganizationalSetting id="V-300" LogFlags="Date,Time" ' +
                'LogFormat="W3C" LogPeriod="Daily" LogTargetW3C="" />')

            $task = (Invoke-Generator -Generator 'New-AnsibleIisLoggingTask' -Rule $orgRule `
                -StigName 'IISServer-10.0' -OrganizationalSetting $blank).Task

            $task.block[0].'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_iisserver_10_0_300_logtargetw3c | default("", true) | length > 0')
        }
    }
}
