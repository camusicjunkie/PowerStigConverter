# Helpers shared by New-StigLabVm.ps1 and Invoke-StigLabRun.ps1; dot-source, do not run.

$script:vboxManage = (Get-Command -Name VBoxManage -ErrorAction Ignore).Source
if (-not $script:vboxManage) {
    $script:vboxManage = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
}

function Invoke-VBoxManage {
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
