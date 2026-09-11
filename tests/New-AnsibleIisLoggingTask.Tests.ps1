#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    # The generator sets OrganizationValueRequired on the rule it was handed, so a rule object
    # cannot be reused: the second call down the same object takes the organisation-value path
    # and goes looking for an org settings file. Every test therefore builds its own rule.
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

        It 'guards the task with the conditional toggle for the rule' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.when | Should-Be 'stig_iisserver_10_0_300_when'
        }
    }

    # Each of these comes off the organisation value object. They are read by the names
    # Get-AnsibleOrganizationValue reports, which are not all the names the STIG rule uses -
    # reading the rule's names instead yields null and the setting is silently dropped.
    Context 'carrying the logging settings through' {

        It 'splits the log flags into a list' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.'ansible.windows.win_dsc'.LogFlags | Should-BeCollection @('Date', 'Time', 'ClientIP')
        }

        It 'splits the log target into a list' {
            $task = New-LoggingTask -Rule (New-LoggingRule)

            $task.'ansible.windows.win_dsc'.LogTargetW3C | Should-BeCollection @('File', 'ETW')
        }

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

    Context 'a rule that duplicates another' {

        It 'skips it' {
            $duplicate = [pscustomobject] @{
                Id = 'V-302'
                Severity = 'medium'
                DuplicateOf = 'V-300'
                OrganizationValueRequired = $false
            }

            $result = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rule = $duplicate } {
                param ($Rule)
                $Rule | New-AnsibleIisLoggingTask -StigName 'IISServer-10.0'
            }

            @($result).Count | Should-Be 0
        }
    }
}

Describe 'New-AnsibleIisLoggingTask idempotency' {

    # The generator used to write OrganizationValueRequired back onto its input purely to steer
    # a filter in the exporter. That filter is gone, so nothing should mutate the rule and the
    # same object can go through twice. See docs/adr/0003.
    Context 'the same rule handed to the generator twice' {

        It 'leaves the rule it was given unchanged' {
            $rule = New-LoggingRule

            $null = New-LoggingTask -Rule $rule

            $rule.OrganizationValueRequired | Should-Be $false
        }

        It 'builds the same task the second time' {
            $rule = New-LoggingRule

            $first = New-LoggingTask -Rule $rule
            $second = New-LoggingTask -Rule $rule

            $second.name | Should-Be $first.name
            $second.'ansible.windows.win_dsc'.LogFormat | Should-Be $first.'ansible.windows.win_dsc'.LogFormat
        }
    }
}
