#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    # A single-item result collapses to a scalar crossing the function boundary either way, so
    # every call site below wraps the call itself in @() rather than relying on this to preserve
    # the array shape.
    function Convert-Task {
        param ($Rule, $RuleType, $StigName = 'WindowsServer-2022-MS', $OrganizationalSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rule = $Rule; RuleType = $RuleType; StigName = $StigName; OrganizationalSetting = $OrganizationalSetting
        } {
            param ($Rule, $RuleType, $StigName, $OrganizationalSetting)
            @($Rule | ConvertTo-AnsibleTask -RuleType $RuleType -StigName $StigName -OrganizationalSetting $OrganizationalSetting)
        }
    }

    function Get-ExpectedToggle {
        param ($TaskId, $StigName = 'WindowsServer-2022-MS')

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ TaskId = $TaskId; StigName = $StigName } {
            param ($TaskId, $StigName)
            Get-AnsibleToggleName -TaskId $TaskId -StigName $StigName
        }
    }

    # Never resolves an organization value: WindowsFeature has no entry in OrganizationData.psd1.
    function New-WindowsFeatureRule {
        param ($Id = 'V-200', $DuplicateOf = '', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = $DuplicateOf
            Name = 'TFTP-Client'; Ensure = 'Absent'; OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function New-AccountPolicyRule {
        param ($Id = 'V-100', $DuplicateOf = '', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = $DuplicateOf
            PolicyName = 'Maximum password age'; PolicyValue = '60'; OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    # Always Group = $true, and gives its two tasks explicit names - a fit for both grouping
    # cases ConvertTo-AnsibleTask decides on its own.
    function New-RootCertificateRule {
        param ($Id = 'V-180', $DuplicateOf = '')

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = $DuplicateOf
            CertificateName = 'DoD Root CA 3'; Thumbprint = 'D73CA91102A2204A36459ED32213B467D7CE97FB'
            OrganizationValueRequired = $true
        }
    }

    function New-RootStore {
        New-TestOrgSetting '<OrganizationalSetting id="V-180" Location="Cert:\LocalMachine\Root" />'
    }
}

Describe 'ConvertTo-AnsibleTask' {

    Context 'a rule that duplicates another' {

        # Covered by the rule it points at, so it must produce no output at all - not an empty
        # task, and not a toggle in defaults/ guarding nothing.
        It 'skips it' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule -DuplicateOf 'V-099') -RuleType 'AccountPolicy')

            $result.Count | Should-Be 0
        }
    }

    Context 'a rule type OrganizationData.psd1 says nothing about' {

        # Resolve-AnsibleOrganizationValue throws for a rule type it has no entry for, so a rule
        # type reaching it here despite the guard would fail the conversion outright rather than
        # producing the task below.
        It 'never resolves an organization value, even when the rule asks for one' {
            $rule = New-WindowsFeatureRule -OrganizationValueRequired $true

            $result = @(Convert-Task -Rule $rule -RuleType 'WindowsFeature')

            $result.Count | Should-Be 1
        }
    }

    Context 'task naming' {

        It 'names an ungrouped task from the rule id, its severity and the detail the adapter reports' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule) -RuleType 'AccountPolicy')

            $result[0].Task.name | Should-Be 'V-100 | MEDIUM | Maximum password age'
        }

        # The adapter names a task outright only for members of a block it builds for itself -
        # here, the register/assert pair a certificate rule always produces.
        It 'keeps the name the adapter supplies for one of a rule''s own tasks' {
            $result = @(Convert-Task -Rule (New-RootCertificateRule) -RuleType 'RootCertificate' -OrganizationalSetting (New-RootStore))

            $result[0].Task.block[0].name | Should-Be 'Gather info for DoD Root CA 3'
        }
    }

    Context 'the conditional toggle' {

        It 'guards an ungrouped task with the toggle for the rule' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule) -RuleType 'AccountPolicy')

            $result[0].Task.when | Should-Be (Get-ExpectedToggle -TaskId 'V-100')
        }

        # A sub-rule shares its base id's toggle, so switching the requirement off has to turn
        # off every task the requirement produced.
        It 'guards a grouped block with the toggle for the base id, not the sub-rule id' {
            $result = @(Convert-Task -Rule (New-RootCertificateRule -Id 'V-180.b') -RuleType 'RootCertificate' `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-180.b" Location="Cert:\LocalMachine\Root" />'))

            $result[0].Task.when | Should-Be (Get-ExpectedToggle -TaskId 'V-180')
        }
    }

    Context 'deciding whether a rule becomes a block' {

        It 'wraps a rule the adapter marks Group into a block named for the base id, severity and group detail' {
            $result = @(Convert-Task -Rule (New-RootCertificateRule) -RuleType 'RootCertificate' -OrganizationalSetting (New-RootStore))

            $result[0].Task.name | Should-BeLikeString 'V-180 | MEDIUM | *'
            $result[0].Task.Contains('block') | Should-BeTrue
        }

        # Sub-rules of one requirement share a block so an operator switches the requirement off
        # rather than one of its halves, even for a rule type whose adapter never asks for a group.
        It 'wraps a sub-rule into a block even when the adapter does not ask for one' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule -Id 'V-100.b') -RuleType 'AccountPolicy')

            $result[0].Task.Contains('block') | Should-BeTrue
        }

        It 'leaves an ordinary single-task rule ungrouped' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule) -RuleType 'AccountPolicy')

            $result[0].Task.Contains('block') | Should-BeFalse
        }
    }
}
