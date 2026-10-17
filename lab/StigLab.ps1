# Helpers shared by New-StigLabVm.ps1 and Invoke-StigLabRun.ps1; dot-source, do not run.

$script:vboxManage = (Get-Command -Name VBoxManage -ErrorAction Ignore).Source
if (-not $script:vboxManage) {
    $script:vboxManage = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
}

function Invoke-VBoxManage {
    # VBoxManage prints its progress bar on stderr; under the callers' Stop that would throw.
    $ErrorActionPreference = 'Continue'
    $output = & $script:vboxManage @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "VBoxManage $($args -join ' ') failed:`n$($output -join "`n")"
    }
    $output
}

# showvminfo --machinereadable as one object; $null when the VM does not exist.
function Get-StigLabVmInfo {
    param ([Parameter(Mandatory)] [string] $Name)

    $lines = & $script:vboxManage showvminfo $Name --machinereadable 2>$null
    if ($LASTEXITCODE -ne 0) { return }

    $info = [ordered] @{}
    foreach ($line in $lines) {
        if ($line -match '^"?(?<key>[^"=]+)"?="?(?<value>.*?)"?$') {
            $info[$Matches.key] = $Matches.value
        }
    }
    [pscustomobject] $info
}

function Get-StigLabVmState {
    param ([Parameter(Mandatory)] [string] $Name)

    (Get-StigLabVmInfo -Name $Name).VMState
}

# lab/.local/<Name>/<ChildPath>, creating the directory; everything under .local is gitignored.
function Get-StigLabStatePath {
    param (
        [Parameter(Mandatory)] [string] $Name,
        [Parameter()] [string] $ChildPath
    )

    $directory = Join-Path $PSScriptRoot ".local\$Name"
    New-Item -Path $directory -ItemType Directory -Force | Out-Null

    if ($ChildPath) { Join-Path $directory $ChildPath } else { $directory }
}

# A bash command in WSL, from a login shell so a pip-installed ansible is on PATH.
function Invoke-StigLabWsl {
    param ([Parameter(Mandatory)] [string] $Command)

    wsl.exe --cd ~ -e bash -lc $Command
}

# A directory in WSL's own filesystem, as both sides name it. Ansible runs from there rather than
# from the repo: WSL need not mount the drive the repo is on, and it treats what it does mount as
# world-writable, which makes Ansible ignore ansible.cfg.
function New-StigLabWslDirectory {
    param ([Parameter(Mandatory)] [string] $ChildPath)

    $distro, $wslHome = Invoke-StigLabWsl 'echo "$WSL_DISTRO_NAME"; echo "$HOME"'
    $wsl = "$wslHome/stiglab/$ChildPath"
    Invoke-StigLabWsl "mkdir -p '$wsl'" | Out-Null

    [pscustomobject] @{
        Wsl     = $wsl
        Windows = "\\wsl.localhost\$distro$($wsl -replace '/', '\')"
    }
}

# A copy of the named STIGs' processed data with the blanks the organization would answer
# filled from LabOrganizationValues.psd1, so a run exercises those rules. Lab only: the values
# are placeholders, and the converter itself still refuses a blank.
function New-StigLabOrganizationData {
    param (
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string[]] $StigName,
        [Parameter()] [string] $Path
    )

    $source = if ($Path) { $Path } else { "$env:LOCALAPPDATA\PowerStig" }
    $processed = 'source\StigData\Processed'
    $target = Get-StigLabStatePath -Name $Name -ChildPath 'stigdata'
    $targetProcessed = Join-Path $target $processed
    Remove-Item -Path $target -Recurse -Force -ErrorAction Ignore
    New-Item -Path $targetProcessed -ItemType Directory -Force | Out-Null

    $values = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'LabOrganizationValues.psd1')
    foreach ($stig in $StigName) {
        Get-ChildItem -Path (Join-Path $source $processed) -File |
            Where-Object { $_.Name -match ('^' + [regex]::Escape($stig) + '-[\d.]+(\.org\.default)?\.xml$') } |
            Copy-Item -Destination $targetProcessed
    }

    foreach ($file in Get-ChildItem -Path $targetProcessed -Filter '*.org.default.xml') {
        [xml] $xml = Get-Content -Path $file.FullName -Raw
        foreach ($node in $xml.OrganizationalSettings.OrganizationalSetting) {
            foreach ($attribute in @($node.Attributes)) {
                if ($attribute.Name -eq 'id' -or $attribute.Value -ne '') { continue }
                $answer = $values.GetEnumerator() | Where-Object { $node.id -like $_.Key } |
                    ForEach-Object { $_.Value[$attribute.Name] } | Select-Object -First 1
                if ($answer) { $attribute.Value = $answer }
            }
        }
        $xml.Save($file.FullName)
    }

    $target
}
