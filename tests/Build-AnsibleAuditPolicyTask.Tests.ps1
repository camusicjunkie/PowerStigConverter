#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-AuditPolicyRule {
        param ($Id = 'V-110')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            SubCategory = 'Credential Validation'
            AuditFlag = 'Success'
        }
    }
}

Describe 'Build-AnsibleAuditPolicyTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleAuditPolicyTask' `
        -Module 'community.windows.win_audit_policy_system' `
        -Factory { New-AuditPolicyRule }

    Context 'the task it builds' {

        It 'carries the subcategory and audit flag the rule names' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAuditPolicyTask' `
                -Rule (New-AuditPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $audit = $task.'community.windows.win_audit_policy_system'
            $audit.subcategory | Should-Be 'Credential Validation'
            $audit.audit_type | Should-Be 'Success'
        }

        It 'names the task for the rule id, its severity and the audit setting' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAuditPolicyTask' `
                -Rule (New-AuditPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-110 | MEDIUM | Credential Validation - Success'
        }
    }
}
