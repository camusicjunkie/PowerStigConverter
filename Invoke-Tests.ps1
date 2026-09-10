<#
.SYNOPSIS
    Runs the PowerStigConverter test suite.

.DESCRIPTION
    Builds the module from Source and runs the Pester suite against the build output, so the
    tests exercise what ships rather than loose script files. The build is handled by
    tests/Initialize-TestModule.ps1 and is skipped when the output is already up to date.

    Tests for defects that have not been fixed yet are tagged KnownDefect and excluded by
    default, so a clean run means "no regressions", not "no known problems". Use -Defects to
    see the outstanding ones.

.PARAMETER Defects
    Run only the KnownDefect tests. Every one of them is expected to fail until the defect it
    describes is fixed.

.PARAMETER All
    Run everything, defects included.

.PARAMETER CodeCoverage
    Measure coverage over Source and write build/coverage.xml in JaCoCo format.

.PARAMETER CI
    Write build/testResults.xml in NUnit format and exit with a non-zero code on failure.

.PARAMETER Path
    Limit the run to specific test files or directories.

.EXAMPLE
    ./Invoke-Tests.ps1

    Run the suite.

.EXAMPLE
    ./Invoke-Tests.ps1 -Defects

    Show the defects that are still outstanding.

.EXAMPLE
    ./Invoke-Tests.ps1 -CI -CodeCoverage

    Run the way a pipeline should: results and coverage on disk, non-zero exit on failure.
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param (
    [Parameter(ParameterSetName = 'Defects')]
    [switch] $Defects,

    [Parameter(ParameterSetName = 'All')]
    [switch] $All,

    [Parameter()]
    [switch] $CodeCoverage,

    [Parameter()]
    [switch] $CI,

    [Parameter()]
    [string[]] $Path
)

$ErrorActionPreference = 'Stop'

# 6.2.0 is the first release carrying the whole Should-* assertion family the suite uses;
# 6.0.0 has no Should-Invoke, Should-MatchString or Should-BeHashtable.
Import-Module -Name Pester -MinimumVersion 6.2.0

$configuration = New-PesterConfiguration
$configuration.Run.Path = if ($Path) { $Path } else { Join-Path $PSScriptRoot 'tests' }
$configuration.Output.Verbosity = 'Detailed'

switch ($PSCmdlet.ParameterSetName) {
    'Defects' { $configuration.Filter.Tag = 'KnownDefect'; break }
    'All' { break }
    default { $configuration.Filter.ExcludeTag = 'KnownDefect' }
}

if ($CodeCoverage) {
    # Coverage has to be measured over the built module, because that is what the tests import.
    # Pointing it at Source instead reports 0%: those files are never executed, ModuleBuilder
    # having concatenated them into the psm1. Line numbers therefore refer to the built file,
    # which carries #Region comments naming the source file each block came from.
    # The tests build the module themselves, but coverage has to name the file it measures
    # before the run starts, so the build has to have happened by now. On a fresh clone it has
    # not, hence building here; the initializer skips the work when the output is already
    # current, so this costs nothing on a repeat run.
    . (Join-Path $PSScriptRoot 'tests/Initialize-TestModule.ps1')

    $built = Get-ChildItem -Path (Join-Path $PSScriptRoot 'build') -Recurse -Filter 'PowerStigConverter.psm1' -ErrorAction Ignore |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $built) {
        throw 'No built module found to measure coverage over, and building one produced nothing.'
    }

    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = $built.FullName
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
    $configuration.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'build/coverage.xml'
}

if ($CI) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = Join-Path $PSScriptRoot 'build/testResults.xml'
    $configuration.Run.Exit = $true
}

Invoke-Pester -Configuration $configuration
