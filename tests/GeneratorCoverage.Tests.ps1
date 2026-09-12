#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Six of thirteen task generators were never executed by any test, because no fixture STIG
    carried a rule of their type and none had a test file of its own. Nothing said so: the suite
    was green, and a refactor touching them would have been verified by nothing.

    This is what says so. It reads the generators off disk rather than taking a list, so a rule
    type added tomorrow is held to the same bar as the thirteen here.
#>

BeforeDiscovery {
    $sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'

    $script:generators = Get-ChildItem (Join-Path $sourceRoot 'Private/Task') -Filter 'New-Ansible*Task.ps1' -Recurse |
        ForEach-Object {
            $body = Get-Content $_.FullName -Raw
            $testPath = Join-Path $PSScriptRoot "$($_.BaseName).Tests.ps1"

            @{
                Name = $_.BaseName
                TestPath = $testPath
                TestBody = if (Test-Path $testPath) { Get-Content $testPath -Raw } else { '' }
                # A generator that resolves organization values has to show that the value reaches
                # the task as a reference rather than a literal.
                ResolvesOrganizationValue = $body -match 'Resolve-AnsibleOrganizationValue'
                # A rule type with a List key in OrganizationData.psd1 has a field the ansible
                # module takes as a list, so a one-element case has to be pinned.
                RuleType = $_.BaseName -replace '^New-Ansible' -replace 'Task$'
            }
        }

    $organizationData = Import-PowerShellDataFile (Join-Path $sourceRoot 'Files/OrganizationData.psd1')
    foreach ($generator in $script:generators) {
        $generator['HasListField'] = $null -ne $organizationData[$generator.RuleType] -and
            $organizationData[$generator.RuleType].ContainsKey('List')
    }
}

Describe 'every task generator is tested' {

    It '<Name> has a test file' -ForEach $generators {
        Test-Path $TestPath | Should-BeTrue
    }

    # The contract carries the cases that are the same for every rule type - the module it emits,
    # the conditional toggle, the duplicate skip, and idempotency over the same rule object. A
    # test file that does not call it has quietly opted out of all four.
    It '<Name> covers the shared generator contract' -ForEach $generators {
        $TestBody | Should-BeLikeString '*Add-GeneratorContractTests*'
    }

    # Item 6. The regression that prompted all this was a one-element list unrolling to a string,
    # which no fixture and no test could have caught.
    It '<Name> pins the shape of a single-valued list' -ForEach ($generators | Where-Object HasListField) {
        $TestBody | Should-BeLikeString "*Context 'a value the task needs as a list'*"
    }

    # Item 7. A value DISA leaves to the adopting organization must never reach the task as a
    # literal - see docs/adr/0003.
    It '<Name> covers the organization value path' -ForEach ($generators | Where-Object ResolvesOrganizationValue) {
        $TestBody | Should-BeLikeString "*Context 'a value the organization decides'*"
    }
}

Describe 'the checklist is discoverable' {

    It 'the contract file says what every generator test has to cover' {
        $contract = Get-Content (Join-Path $PSScriptRoot 'GeneratorContract.ps1') -Raw

        $contract | Should-BeLikeString '*the ansible module or DSC resource it emits*'
        $contract | Should-BeLikeString '*a single-valued list stays a list*'
    }
}
