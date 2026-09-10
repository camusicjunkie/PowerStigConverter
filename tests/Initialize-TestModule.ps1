<#
.SYNOPSIS
    Builds PowerStigConverter from Source and imports the result, so tests exercise exactly
    what ships rather than loose script files.

.DESCRIPTION
    Dot-source this from a BeforeAll block. Pester 6 discovers and runs each test file
    individually, so every file must arrange its own module import; the build itself is
    skipped when the output is already newer than every file under Source, which keeps the
    cost to one build per session instead of one per test file.

    Importing the built module (rather than dot-sourcing Source/*.ps1) is what makes
    InModuleScope able to reach the private functions, and is the only way the script-scope
    data that prefix.ps1 sets up - organizationData, accountPolicyData, securityOptionData -
    is present the way it is at runtime.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$sourcePath = Join-Path $repoRoot 'Source'

$newestSource = Get-ChildItem -Path $sourcePath -Recurse -File |
    Sort-Object -Property LastWriteTimeUtc -Descending |
    Select-Object -First 1

$built = Get-ChildItem -Path (Join-Path $repoRoot 'build') -Recurse -Filter 'PowerStigConverter.psd1' -ErrorAction Ignore |
    Sort-Object -Property LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $built -or $built.LastWriteTimeUtc -lt $newestSource.LastWriteTimeUtc) {
    Import-Module -Name ModuleBuilder
    $built = Build-Module -SourcePath (Join-Path $sourcePath 'build.psd1') -Passthru |
        Select-Object -ExpandProperty Path |
        Get-Item
}

Import-Module -Name $built.FullName -Force
