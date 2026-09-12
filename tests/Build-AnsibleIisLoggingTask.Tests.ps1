#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    # A fresh rule per case, so a failure cannot be an artefact of the case before it.
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

    # V-218741 of the IIS 10.0 Site STIG, which asks for the Connection and Warning request
    # headers to be logged. Built from xml rather than a pscustomobject because the generator
    # reads .Entry off the element, and only a rule read out of the processed STIG has that.
    function New-CustomFieldRule {
        param (
            [string] $Entry = @'
        <Entry>
          <SourceType>RequestHeader</SourceType>
          <SourceName>Connection</SourceName>
        </Entry>
        <Entry>
          <SourceType>RequestHeader</SourceType>
          <SourceName>Warning</SourceName>
        </Entry>
'@
        )

        [xml] $document = @"
<Rule id="V-218741" severity="medium" conversionstatus="pass" dscresource="XWebsite">
  <DuplicateOf />
  <IsNullOrEmpty>False</IsNullOrEmpty>
  <LogCustomFieldEntry>$Entry</LogCustomFieldEntry>
  <LogFlags />
  <LogFormat>W3C</LogFormat>
  <LogPeriod />
  <LogTargetW3C />
  <OrganizationValueRequired>False</OrganizationValueRequired>
  <OrganizationValueTestString />
</Rule>
"@

        $document.Rule
    }

    function New-LoggingTask {
        param ($Rule)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rule = $Rule } {
            param ($Rule)
            ($Rule | ConvertTo-AnsibleTask -RuleType 'IisLogging' -StigName 'IISServer-10.0').Task
        }
    }
}

Describe 'Build-AnsibleIisLoggingTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleIisLoggingTask' `
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

    # Read by the names the resolution reports, not the rule's - reading the rule's yields
    # null and the setting is silently dropped.
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

    # Item 6. A LogTargetW3C of just File unrolled to a string and was written as a scalar.
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

    # The custom fields reach win_dsc two deep - a list of hashtables, each holding one
    # DSC_LogCustomField - because that is how the DSC resource takes an array of embedded
    # instances.
    Context 'the custom log fields the rule carries' {

        It 'builds one DSC_LogCustomField per entry, in rule order' {
            $fields = (New-LoggingTask -Rule (New-CustomFieldRule)).'ansible.windows.win_dsc'.LogCustomFields

            @($fields).Count | Should-Be 2
            $fields[0].DSC_LogCustomField.SourceName | Should-Be 'Connection'
            $fields[1].DSC_LogCustomField.SourceName | Should-Be 'Warning'
        }

        # The resource keys its fields by name and the rule carries none - only the source the
        # field comes from, which is what makes the pair unique.
        It 'names each field for the source type and name it joins' {
            $fields = (New-LoggingTask -Rule (New-CustomFieldRule)).'ansible.windows.win_dsc'.LogCustomFields

            $fields.DSC_LogCustomField.LogFieldName |
                Should-BeCollection @('RequestHeader-Connection', 'RequestHeader-Warning')
        }

        It 'carries the source type and name through unchanged' {
            $field = (New-LoggingTask -Rule (New-CustomFieldRule)).'ansible.windows.win_dsc'.LogCustomFields[0].DSC_LogCustomField

            $field.SourceType | Should-Be 'RequestHeader'
            $field.SourceName | Should-Be 'Connection'
        }

        # One Entry comes off the element as a single node rather than a collection, which is
        # where a shape like this usually unrolls to a lone hashtable.
        It 'keeps a single entry a list rather than unrolling it' {
            $single = New-CustomFieldRule -Entry @'
        <Entry>
          <SourceType>ResponseHeader</SourceType>
          <SourceName>Content-Type</SourceName>
        </Entry>
'@

            $fields = (New-LoggingTask -Rule $single).'ansible.windows.win_dsc'.LogCustomFields

            $fields -is [array] | Should-BeTrue
            @($fields).Count | Should-Be 1
            $fields[0].DSC_LogCustomField.LogFieldName | Should-Be 'ResponseHeader-Content-Type'
        }

        It 'leaves the key off the resource entirely when the rule has no custom fields' {
            $task = New-LoggingTask -Rule (New-CustomFieldRule -Entry '')

            $task.'ansible.windows.win_dsc'.Keys | Should-NotContainCollection @('LogCustomFields')
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
            $dsc = (Invoke-Generator -Generator 'Build-AnsibleIisLoggingTask' -Rule $orgRule `
                -StigName 'IISServer-10.0' -OrganizationalSetting $answered).Task.'ansible.windows.win_dsc'

            $dsc.LogFormat | Should-Be '{{ stig_iisserver_10_0_300_logformat }}'
            $dsc.LogTargetW3C | Should-Be '{{ stig_iisserver_10_0_300_logtargetw3c }}'
        }

        It 'guards an unanswered field with an assert naming that field' {
            $blank = New-ContractOrgSetting ('<OrganizationalSetting id="V-300" LogFlags="Date,Time" ' +
                'LogFormat="W3C" LogPeriod="Daily" LogTargetW3C="" />')

            $task = (Invoke-Generator -Generator 'Build-AnsibleIisLoggingTask' -Rule $orgRule `
                -StigName 'IISServer-10.0' -OrganizationalSetting $blank).Task

            $task.block[0].'ansible.builtin.assert'.that |
                Should-BeCollection @('stig_iisserver_10_0_300_logtargetw3c | default("", true) | length > 0')
        }
    }
}
