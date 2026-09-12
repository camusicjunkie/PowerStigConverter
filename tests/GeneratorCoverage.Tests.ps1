#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    Six of thirteen generators were once never executed by any test, and nothing said so. This
    does. It reads the generators off disk, so a new rule type meets the same bar.
#>

BeforeDiscovery {
    $sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'

    $script:generators = Get-ChildItem (Join-Path $sourceRoot 'Private/Task') -Include 'New-Ansible*Task.ps1', 'Build-Ansible*Task.ps1' -Recurse |
        ForEach-Object {
            $body = Get-Content $_.FullName -Raw
            $testPath = Join-Path $PSScriptRoot "$($_.BaseName).Tests.ps1"

            @{
                Name = $_.BaseName
                TestPath = $testPath
                TestBody = if (Test-Path $testPath) { Get-Content $testPath -Raw } else { '' }
                # Judged on OrganizationData.psd1 below, not on whether the file mentions the
                # resolver - a rule type whose values the shared module resolves would otherwise
                # stop being required to cover the path.
                ResolvesOrganizationValue = $false
                # A rule type with a List key in OrganizationData.psd1 has a field the ansible
                # module takes as a list, so a one-element case has to be pinned.
                RuleType = $_.BaseName -replace '^(New|Build)-Ansible' -replace 'Task$'
            }
        }

    $organizationData = Import-PowerShellDataFile (Join-Path $sourceRoot 'Files/OrganizationData.psd1')
    foreach ($generator in $script:generators) {
        $generator['ResolvesOrganizationValue'] = $organizationData.ContainsKey($generator.RuleType)
        $generator['HasListField'] = $null -ne $organizationData[$generator.RuleType] -and
            $organizationData[$generator.RuleType].ContainsKey('List')
    }
}

Describe 'every task generator is tested' {

    It '<Name> has a test file' -ForEach $generators {
        Test-Path $TestPath | Should-BeTrue
    }

    # A file that does not call the contract has quietly opted out of all four shared cases.
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
