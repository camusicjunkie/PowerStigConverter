#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-AuditSettingRule {
        param (
            $Id = 'V-120', $Namespace = 'root/cimv2', $Query = 'SELECT * FROM Win32_LogicalDisk',
            $Property = 'FileSystem', $DesiredValue = 'NTFS', $Operator = '-eq'
        )

        [pscustomobject] @{
            Id = $Id
            Severity = 'low'
            DuplicateOf = ''
            Query = $Query
            Property = $Property
            DesiredValue = $DesiredValue
            Operator = $Operator
            Namespace = $Namespace
        }
    }

    function Get-AuditSettingTask {
        param ($Rule = (New-AuditSettingRule))

        (Invoke-Generator -Generator 'Build-AnsibleAuditSettingTask' -Rule $Rule -StigName 'WindowsServer-2022-MS').Task
    }

    function Get-Gather {
        param ($Task)
        ($Task.block | Where-Object { $_.Contains('ansible.windows.win_powershell') }).'ansible.windows.win_powershell'
    }
}

# The rule's own query, run by a fixed script; win_dsc is out (docs/adr/0024).
Describe 'Build-AnsibleAuditSettingTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleAuditSettingTask' `
        -Module 'ansible.windows.win_powershell' `
        -Factory { New-AuditSettingRule }

    Context 'the task it builds' {

        It 'passes the query, property, operator and desired value as parameters' {
            (Get-Gather (Get-AuditSettingTask)).parameters | Should-BeEquivalent ([ordered] @{
                Query = 'SELECT * FROM Win32_LogicalDisk'
                Property = 'FileSystem'
                Operator = '-eq'
                DesiredValue = 'NTFS'
                Namespace = 'root/cimv2'
            })
        }

        It 'runs the same script for two different rules' {
            $other = New-AuditSettingRule -Id 'V-121' -Namespace '' -Query 'SELECT * FROM Win32_OperatingSystem' `
                -Property 'Version' -DesiredValue '10.0.22621' -Operator '-le'

            (Get-Gather (Get-AuditSettingTask -Rule $other)).script | Should-Be (Get-Gather (Get-AuditSettingTask)).script
        }

        It 'asserts the gather it registered found nothing out of compliance' {
            $task = Get-AuditSettingTask
            $register = ($task.block | Where-Object { $_.Contains('ansible.windows.win_powershell') }).register
            $assert = ($task.block | Where-Object { $_.Contains('ansible.builtin.assert') }).'ansible.builtin.assert'

            $register | Should-Be (Get-ExpectedRegisterName -TaskId 'V-120' -StigName 'WindowsServer-2022-MS' -Suffix 'noncompliant')
            $assert.that | Should-Be "$register.output | length == 0"
        }

        It 'names the property, operator and desired value in the failure, with the values found' {
            $assert = ((Get-AuditSettingTask).block | Where-Object { $_.Contains('ansible.builtin.assert') }).'ansible.builtin.assert'

            $register = Get-ExpectedRegisterName -TaskId 'V-120' -StigName 'WindowsServer-2022-MS' -Suffix 'noncompliant'
            $assert.fail_msg | Should-Be "NTFS -eq FileSystem is false for: {{ $register.output | join(', ') }}"
        }

        # The comparison is evaluated desired value first, so the names read that way too.
        It 'names the tasks with the desired value before the operator and property' {
            $rule = New-AuditSettingRule -Query 'SELECT * FROM Win32_OperatingSystem' -Property 'Version' `
                -DesiredValue '10.0.22621' -Operator '-le'
            $task = Get-AuditSettingTask -Rule $rule

            $task.name | Should-Be 'V-120 | LOW | Audit 10.0.22621 -le Version'
            $task.block.name | Should-BeCollection @('Gather 10.0.22621 -le Version', 'Assert 10.0.22621 -le Version')
        }
    }

    # The script body run here against a stub Get-CimInstance, as win_powershell would run it.
    Context 'the script it runs' {

        BeforeAll {
            function Invoke-AuditScript {
                param ($Rule, $Instance)

                $gather = Get-Gather (Get-AuditSettingTask -Rule $Rule)
                $parameters = @{} + $gather.parameters
                $Ansible = [pscustomobject] @{ Changed = $true }
                $stub = $Instance
                function Get-CimInstance { $stub }

                $output = & ([scriptblock]::Create($gather.script)) @parameters
                [pscustomobject] @{ Output = @($output); Changed = $Ansible.Changed }
            }
        }

        It 'outputs nothing for an instance that complies, and reports no change' {
            $result = Invoke-AuditScript -Rule (New-AuditSettingRule) -Instance ([pscustomobject] @{ FileSystem = 'NTFS' })

            $result.Output.Count | Should-Be 0
            $result.Changed | Should-BeFalse
        }

        It 'outputs the actual value of each instance that does not comply' {
            $result = Invoke-AuditScript -Rule (New-AuditSettingRule) -Instance @(
                [pscustomobject] @{ FileSystem = 'NTFS' }
                [pscustomobject] @{ FileSystem = 'FAT32' }
            )

            $result.Output | Should-BeCollection @('FAT32')
        }

        # The desired value is on the left, which is the order PowerStig's data is written for (#209).
        It 'puts the desired value on the left of the comparison' {
            $rule = New-AuditSettingRule -Namespace '' -Query 'SELECT * FROM Win32_OperatingSystem' -Property 'Version' `
                -DesiredValue '10.0.22621' -Operator '-le'

            (Invoke-AuditScript -Rule $rule -Instance ([pscustomobject] @{ Version = '10.0.26300' })).Output.Count | Should-Be 0
            (Invoke-AuditScript -Rule $rule -Instance ([pscustomobject] @{ Version = '10.0.19045' })).Output |
                Should-BeCollection @('10.0.19045')
        }

        It 'throws on an operator it does not know, naming it' {
            $rule = New-AuditSettingRule -Operator 'eq'

            { Invoke-AuditScript -Rule $rule -Instance ([pscustomobject] @{ FileSystem = 'NTFS' }) } |
                Should-Throw -ExceptionMessage "*'eq'*"
        }
    }

    # Get-CimInstance defaults the namespace itself, so sending an empty one is worse than none.
    Context 'a rule that does not name a namespace' {

        It 'leaves Namespace out rather than sending it empty' {
            (Get-Gather (Get-AuditSettingTask -Rule (New-AuditSettingRule -Namespace ''))).parameters.Contains('Namespace') |
                Should-BeFalse
        }
    }
}
