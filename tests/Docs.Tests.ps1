#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    The ADRs are numbered by hand. This catches a duplicate or skipped number and an ADR without
    a status, which nothing else reads.
#>

BeforeDiscovery {
    $script:adrs = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/adr') -Filter '*.md' |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

Describe 'docs/adr' {
    It '<Name> is named NNNN-slug.md and opens with a status' -ForEach $script:adrs {
        $Name | Should -Match '^\d{4}-.+\.md$'
        (Get-Content $Path -TotalCount 2) -join "`n" | Should -Match '^---\nstatus: \w+'
    }

    It 'numbers run from 0001 with no duplicate or gap' {
        $numbers = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/adr') -Filter '*.md' |
            ForEach-Object { [int]$_.Name.Substring(0, 4) } | Sort-Object
        $numbers | Should -Be (1..$numbers.Count)
    }
}
