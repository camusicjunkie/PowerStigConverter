#requires -Modules InvokeBuild

[CmdletBinding()]
param(
    [string[]]
    $Tag,

    # Test files or folders for QuickTest; all of tests/ when not given
    [string[]]
    $TestPath,

    [string]
    $NuGetApiKey
)

$ModuleName = 'PowerStigConverter'
$OutputRoot = Join-Path $PSScriptRoot 'build'
$SourceRoot = Join-Path $PSScriptRoot 'Source'
$TestRoot = Join-Path $PSScriptRoot 'tests'

# 6.2.0 is the first release carrying the whole Should-* assertion family the suite uses
$PesterVersion = '6.2.0'

# The built manifest: build/PowerStigConverter/<version>/PowerStigConverter.psd1
function Get-BuiltManifest {
    $manifest = @(Get-ChildItem -Path (Join-Path $OutputRoot $ModuleName) -Filter "$ModuleName.psd1" -Recurse -ErrorAction SilentlyContinue)
    if ($manifest.Count -ne 1) {
        throw "Expected one built module under $OutputRoot, found $($manifest.Count). Run the Clean and Build tasks."
    }
    $manifest[0]
}

# Runs Pester over the built module. Each test file imports the build itself through
# tests/Initialize-TestModule.ps1, which finds the one these tasks just produced.
function Invoke-TestRun {
    param (
        [string[]] $Path,

        # The tests to run; KnownDefect tests are excluded when none is given
        [string[]] $IncludeTag,

        [switch] $CodeCoverage,

        [string] $Verbosity = 'Detailed'
    )

    Import-Module -Name Pester -MinimumVersion $PesterVersion -Force

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $Path
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = $Verbosity

    if ($IncludeTag) {
        $configuration.Filter.Tag = $IncludeTag
    }
    else {
        # Tests for defects not yet fixed: a clean run means no regressions, not no known problems
        $configuration.Filter.ExcludeTag = 'KnownDefect'
    }

    if ($CodeCoverage) {
        # Measured over the built psm1, because that is what the tests import. Pointed at Source
        # it reports 0%: ModuleBuilder concatenates those files, so they never run as themselves.
        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.Path = (Get-BuiltManifest).FullName -replace 'd1$', 'm1'
        $configuration.CodeCoverage.OutputPath = Join-Path $OutputRoot 'codecoverage.xml'
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputPath = Join-Path $OutputRoot 'testResults.xml'
    }

    Invoke-Pester -Configuration $configuration
}

Enter-Build {
    Set-BuildHeader {
        param($Path)
        ''
        '=' * 79
        Write-Build Cyan "$($Task.Name)"
        ''
        Write-Build DarkGray "$(Get-BuildSynopsis $Task)"
        '-' * 79
        Write-Build DarkGray "  $Path"
        Write-Build DarkGray "  $($Task.InvocationInfo.ScriptName):$($Task.InvocationInfo.ScriptLineNumber)"
        ''
    }
}

# Synopsis: Default task
Task . Clean, Analyze, Build, Test

# Synopsis: Get the next build version
Task GetNextVersion {
    $gitversion = Exec { gitversion | ConvertFrom-Json }
    $env:NextBuildVersion = $gitversion.MajorMinorPatch
}

# Synopsis: Display build information
Task ShowInfo {
    Write-Build Gray ('PowerShell version:         {0}' -f $PSVersionTable.PSVersion.ToString())
    Write-Build Gray ('OS:                         {0}' -f [System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
    Write-Build Gray
}

# Synopsis: Remove the built module and test results
Task Clean {
    # build/modules holds the dependencies PSDepend installed, so only the build output goes
    $paths = @(
        Join-Path $OutputRoot $ModuleName
        Join-Path $OutputRoot 'testResults.xml'
        Join-Path $OutputRoot 'codecoverage.xml'
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Remove-Item $path -Recurse -Force
        }
    }
}

# Synopsis: Build a shippable release
Task Build GetNextVersion, {
    if (-not $env:NextBuildVersion) {
        throw 'GitVersion did not produce a version.'
    }
    Build-Module -Path "$SourceRoot/build.psd1" -Version $env:NextBuildVersion
}

# Synopsis: Run all Pester tests against the built module, with coverage and NUnit results
Task Test {
    $testResults = Invoke-TestRun -Path $TestRoot -IncludeTag $Tag -CodeCoverage

    Equals $testResults.FailedCount 0
}

# Synopsis: Build at version 0.0.0 without GitVersion, for local test runs
Task DevBuild {
    # A second version beside an earlier build would make the built module ambiguous
    $output = Join-Path $OutputRoot $ModuleName
    if (Test-Path $output) {
        Remove-Item $output -Recurse -Force
    }
    Build-Module -Path "$SourceRoot/build.psd1" -Version '0.0.0'
}

# Synopsis: Build, then run the given tests without coverage
Task QuickTest DevBuild, {
    $path = if ($TestPath) { $TestPath } else { $TestRoot }
    $testResults = Invoke-TestRun -Path $path -IncludeTag $Tag -Verbosity Normal

    Equals $testResults.FailedCount 0
}

# Synopsis: Build, then run only the KnownDefect tests, each of which is expected to fail
Task Defects DevBuild, {
    $null = Invoke-TestRun -Path $TestRoot -IncludeTag 'KnownDefect'
}

# Synopsis: Lint the module source with PSScriptAnalyzer
Task Analyze ParseWindowsPowerShell, {
    # The tests are left out: Pester's BeforeAll scoping reads as unused variables
    $findings = foreach ($path in 'Private', 'Public', 'prefix.ps1') {
        Invoke-ScriptAnalyzer -Path "$SourceRoot/$path" -Recurse -Severity Warning, Error
    }

    if ($findings) {
        $findings | Format-Table RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200
        throw "PSScriptAnalyzer found $(@($findings).Count) issue(s)."
    }
}

# Synopsis: Check Windows PowerShell 5.1 can parse every script, when running on 7 beside it
Task ParseWindowsPowerShell -If ($PSVersionTable.PSEdition -eq 'Core' -and (Get-Command -Name powershell.exe -ErrorAction Ignore)) {
    # 5.1's parser rejects some syntax 7 accepts, such as an if with no else as a hashtable
    # value. Parsing under 5.1 costs seconds; finding out from the CI leg costs a run.
    $parseErrors = powershell.exe -NoProfile -NonInteractive -Command {
        param ($Root)

        $files = @(Get-ChildItem -Path $Root -Filter '*.ps1' -File) +
            @(Get-ChildItem -Path "$Root/Source", "$Root/tests", "$Root/BuildTools" -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1')

        foreach ($file in $files) {
            $errors = $null
            [void] [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $errors)
            foreach ($parseError in $errors) {
                '{0}:{1}: {2}' -f $file.FullName, $parseError.Extent.StartLineNumber, $parseError.Message
            }
        }
    } -args $PSScriptRoot

    if ($parseErrors) {
        throw "Windows PowerShell 5.1 cannot parse:`n$($parseErrors -join "`n")"
    }
}

# Synopsis: Publish
Task Publish PublishToPSGallery

# Synopsis: Publish the built module to the PowerShell Gallery
Task PublishToPSGallery {
    $manifest = Get-BuiltManifest
    $version = (Import-PowerShellDataFile -Path $manifest.FullName).ModuleVersion

    $apiKey = if ($NuGetApiKey) { $NuGetApiKey } else { $env:NuGetApiKey }
    if (-not $apiKey) {
        throw 'No API key. Pass -NuGetApiKey or set $env:NuGetApiKey.'
    }

    Write-Build Gray "  Publishing $ModuleName $version to PSGallery"
    Publish-Module -Path $manifest.Directory.FullName -NuGetApiKey $apiKey -Repository PSGallery -ErrorAction Stop
}

# Synopsis: Empty task that's useful to test the bootstrap process
Task Noop { }
