#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-RootCertificateRule {
        param ($Id = 'V-180', $OrganizationValueRequired = $true)

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            CertificateName = 'DoD Root CA 3'
            Thumbprint = 'D73CA91102A2204A36459ED32213B467D7CE97FB'
            Location = ''
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function Get-RootCertificateTask {
        param ($Rule, $OrganizationalSetting = @{})

        (Invoke-Generator -Generator 'New-AnsibleRootCertificateTask' -Rule $Rule `
            -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $OrganizationalSetting).Task
    }

    function New-RootStore {
        New-ContractOrgSetting '<OrganizationalSetting id="V-180" Location="Cert:\LocalMachine\Root" />'
    }
}

# The certificate store is always an organization value, so every rule of this type takes the
# organization path. The rule used to be dropped outright when the value was blank, which left a
# STIG requirement silently absent from the role - see docs/adr/0001.
Describe 'New-AnsibleRootCertificateTask' {

    Add-GeneratorContractTests -Generator 'New-AnsibleRootCertificateTask' `
        -Module 'community.windows.win_certificate_info' `
        -Factory { New-RootCertificateRule }

    Context 'the task it builds' {

        It 'gathers the certificate by thumbprint' {
            $task = Get-RootCertificateTask -Rule (New-RootCertificateRule) -OrganizationalSetting (New-RootStore)
            $gather = $task.block | Where-Object { $_.Contains('community.windows.win_certificate_info') }

            $gather.'community.windows.win_certificate_info'.thumbprint |
                Should-Be 'D73CA91102A2204A36459ED32213B467D7CE97FB'
        }

        It 'asserts the certificate exists in the store' {
            $task = Get-RootCertificateTask -Rule (New-RootCertificateRule) -OrganizationalSetting (New-RootStore)
            $assert = $task.block | Where-Object { $_.name -like 'Assert *' }

            $assert.'ansible.builtin.assert'.fail_msg | Should-BeLikeString '*DoD Root CA 3*'
        }

        It 'names the block for the base id, its severity and the certificate' {
            $task = Get-RootCertificateTask -Rule (New-RootCertificateRule) -OrganizationalSetting (New-RootStore)

            $task.name | Should-BeLikeString 'V-180 | MEDIUM | *certificate store'
        }
    }

    Context 'a value the organization decides' {

        # PowerStig holds a store path; win_certificate_info takes the store and its location as
        # separate parameters. Both are taken at generation time so defaults/ holds the values the
        # module actually consumes, and the assert's non-empty check is about those values.
        # See docs/adr/0003.
        It 'interpolates a variable for the store and another for its location' {
            $task = Get-RootCertificateTask -Rule (New-RootCertificateRule) -OrganizationalSetting (New-RootStore)
            $gather = ($task.block | Where-Object { $_.Contains('community.windows.win_certificate_info') }).'community.windows.win_certificate_info'

            $gather.store_name | Should-Be '{{ stig_server_2022_180_store_name }}'
            $gather.store_location | Should-Be '{{ stig_server_2022_180_store_location }}'
        }

        It 'guards both unanswered variables with an assert, rather than dropping the rule' {
            $task = Get-RootCertificateTask -Rule (New-RootCertificateRule) `
                -OrganizationalSetting (New-ContractOrgSetting '<OrganizationalSetting id="V-180" Location="" />')

            $guard = $task.block | Where-Object { $_.name -like 'Assert the organization values*' }

            $guard | Should-NotBeNull
            $guard.'ansible.builtin.assert'.that | Should-BeCollection @(
                'stig_server_2022_180_store_name | default("", true) | length > 0'
                'stig_server_2022_180_store_location | default("", true) | length > 0'
            )
        }

        It 'builds no such guard once the store has been answered' {
            $task = Get-RootCertificateTask -Rule (New-RootCertificateRule) -OrganizationalSetting (New-RootStore)

            $task.block | Where-Object { $_.name -like 'Assert the organization values*' } | Should-BeNull
        }
    }
}
