<#
.SYNOPSIS
    Installs the suite's dependencies into whichever engine is running this script.

.DESCRIPTION
    Run once per engine by the CI workflow. It has to run *inside* the engine under test rather
    than beside it, because the two read different module directories: Windows PowerShell 5.1
    looks in Program Files\WindowsPowerShell\Modules and PowerShell 7 in Program Files\PowerShell
    \Modules, so installing from one leaves the other with nothing.

    A script rather than an inline run block because the workflow cannot say `shell: ${{ ... }}`
    - `shell` is validated against a fixed list of values before any expression is evaluated, so
    templating it fails the whole workflow at compile time. The step therefore runs under pwsh and
    invokes the engine as a child process, and a -File argument avoids quoting a script inside a
    YAML string inside a command line.
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'

# 5.1 ships PowerShellGet 1.0.0.1, which negotiates TLS 1.0 against a gallery that requires 1.2,
# and prompts for the NuGet provider on first install. Guarded by edition rather than run
# everywhere: on 7 there is no NuGet provider to find and Install-PackageProvider fails with
# "No match was found for the specified search criteria", so it is an error there, not a no-op.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# The runner ships Pester 5, which cannot run this suite: Should-Invoke and Should-MatchString
# arrived in 6.2.0. -SkipPublisherCheck is needed because the preinstalled Pester is signed by
# Microsoft and 6.x is not.
Install-Module -Name Pester -MinimumVersion 6.2.0 -Force -SkipPublisherCheck

# ModuleBuilder assembles the module the tests import; powershell-yaml and Plaster are the
# module's own runtime requirements, declared in its manifest.
Install-Module -Name ModuleBuilder, powershell-yaml, Plaster -Force

# Printed so a failing run says which engine and which module versions produced it.
$PSVersionTable | Out-String
Get-Module -ListAvailable Pester, ModuleBuilder, powershell-yaml, Plaster |
    Select-Object Name, Version |
    Sort-Object Name |
    Format-Table -AutoSize |
    Out-String
