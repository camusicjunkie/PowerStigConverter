#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    GeneratorCoverage.Tests.ps1 guarantees a floor for the thirteen task generators. Nothing did
    the same for the rest of Source/, which is how five functions with a file of their own ended
    up with no test naming them (#39) before anything said so.

    This repo's one-function-per-file convention makes the rule clean: the function a file is
    named for is that file's own function and needs a Describe somewhere under tests/. A helper
    defined alongside it in the same file is covered through its owner and is exempt, whether or
    not it happens to get a Describe of its own.
#>

BeforeDiscovery {
    $sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'

    $script:sourceFiles = Get-ChildItem $sourceRoot -Filter '*.ps1' -Recurse |
        Where-Object Name -NE 'prefix.ps1'

    $testBody = (Get-ChildItem $PSScriptRoot -Filter '*.Tests.ps1' | Get-Content -Raw) -join "`n"

    $script:ownFunctions = $script:sourceFiles | ForEach-Object {
        @{
            Name = $_.BaseName
            IsDescribed = $testBody -match "(?m)^Describe\s+['""]$([regex]::Escape($_.BaseName))['""]"
        }
    }
}

Describe 'every function with a file of its own is tested' {

    It '<Name> has a test file that Describes it' -ForEach $ownFunctions {
        $IsDescribed | Should-BeTrue
    }
}
