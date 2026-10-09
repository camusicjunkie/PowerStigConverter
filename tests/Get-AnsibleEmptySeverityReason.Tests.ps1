#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Get-AnsibleEmptySeverityReason' {

    # The one wording the empty severity file and the empty toggle file share. See #133.
    It 'names the STIG and the severity no task was generated at' {
        $reason = InModuleScope -ModuleName PowerStigConverter {
            Get-AnsibleEmptySeverityReason -StigName 'WindowsServer-2022-MS' -Severity 'low'
        }
        $reason | Should-BeString '# No tasks were generated for WindowsServer-2022-MS at low severity.'
    }

    # Both exporters read converted tasks (ADR 0016), so rules skipped by dispatch empty the file
    # too; the line must not say the STIG has none. See #134.
    It 'does not claim the STIG has no rules at that severity' {
        $reason = InModuleScope -ModuleName PowerStigConverter {
            Get-AnsibleEmptySeverityReason -StigName 'WindowsServer-2022-MS' -Severity 'high'
        }
        $reason | Should-NotBeLikeString '*has no*rules*'
    }
}
