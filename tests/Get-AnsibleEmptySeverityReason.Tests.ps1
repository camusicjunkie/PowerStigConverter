#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
}

Describe 'Get-AnsibleEmptySeverityReason' {

    # The one wording the empty severity file and the empty toggle file share. See #133.
    It 'names the STIG and the severity it has no rules at' {
        $reason = InModuleScope -ModuleName PowerStigConverter {
            Get-AnsibleEmptySeverityReason -StigName 'WindowsServer-2022-MS' -Severity 'low'
        }
        $reason | Should-BeString '# WindowsServer-2022-MS has no low severity rules.'
    }
}
