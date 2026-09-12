#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-AuditSettingRule {
        param ($Id = 'V-120', $Namespace = 'root/cimv2')

        [pscustomobject] @{
            Id = $Id
            Severity = 'low'
            DuplicateOf = ''
            Query = 'SELECT * FROM Win32_LogicalDisk'
            Property = 'FileSystem'
            DesiredValue = 'NTFS'
            Operator = 'eq'
            Namespace = $Namespace
        }
    }
}

# There is no ansible module covering a WMI audit, so this one goes through win_dsc.
Describe 'Build-AnsibleAuditSettingTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleAuditSettingTask' `
        -Module 'ansible.windows.win_dsc' `
        -Factory { New-AuditSettingRule }

    Context 'the task it builds' {

        It 'uses the AuditSetting DSC resource' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAuditSettingTask' `
                -Rule (New-AuditSettingRule) -StigName 'WindowsServer-2022-MS').Task

            $task.'ansible.windows.win_dsc'.resource_name | Should-Be 'AuditSetting'
        }

        It 'carries the query, property, desired value and operator' {
            $dsc = (Invoke-Generator -Generator 'Build-AnsibleAuditSettingTask' `
                -Rule (New-AuditSettingRule) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_dsc'

            $dsc.Query | Should-Be 'SELECT * FROM Win32_LogicalDisk'
            $dsc.Property | Should-Be 'FileSystem'
            $dsc.DesiredValue | Should-Be 'NTFS'
            $dsc.Operator | Should-Be 'eq'
        }

        It 'names the task for the assertion it makes' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAuditSettingTask' `
                -Rule (New-AuditSettingRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-120 | LOW | Audit that FileSystem eq NTFS'
        }
    }

    # The DSC resource defaults the namespace itself, so sending an empty one would be worse than
    # sending none at all.
    Context 'a rule that does not name a namespace' {

        It 'leaves Namespace out rather than sending it empty' {
            $dsc = (Invoke-Generator -Generator 'Build-AnsibleAuditSettingTask' `
                -Rule (New-AuditSettingRule -Namespace '') -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_dsc'

            $dsc.Contains('Namespace') | Should-BeFalse
        }

        It 'includes Namespace when the rule does name one' {
            $dsc = (Invoke-Generator -Generator 'Build-AnsibleAuditSettingTask' `
                -Rule (New-AuditSettingRule) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_dsc'

            $dsc.Namespace | Should-Be 'root/cimv2'
        }
    }
}
