<#
.SYNOPSIS
    Builds a Windows Server VirtualBox VM ready to have a generated role applied to it.

.DESCRIPTION
    Creates the VM, installs Windows unattended, runs Initialize-StigLabGuest.ps1 inside it at
    first logon, then waits for it to power itself off and takes the snapshot Invoke-StigLabRun
    restores before every run. Nothing needs the VM's console.

    The guest account's password is generated here and kept, with the rest of what a run needs
    to reach the VM, in lab/.local/<Name>/vm.json - gitignored, like everything under .local.

.EXAMPLE
    ./lab/New-StigLabVm.ps1 -Name stig-ws2025 -IsoPath D:\LabSources\ISOs\Server2025.iso -IPAddress 192.168.56.25
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateLength(1, 15)]
    [string] $Name,

    [Parameter(Mandatory)]
    [string] $IsoPath,

    [Parameter(Mandatory)]
    [string] $IPAddress,

    # 4 is Datacenter (Desktop Experience) on retail Server 2022 and 2025 media.
    [Parameter()]
    [int] $ImageIndex = 4,

    # Microsoft's published KMS client key for Server 2025 Datacenter; it only skips the key prompt.
    [Parameter()]
    [string] $ProductKey = 'D764K-2NDRG-47T6Q-P8T8W-YP6DF',

    [Parameter()]
    [string] $HostOnlyAdapter = 'VirtualBox Host-Only Ethernet Adapter',

    [Parameter()]
    [int] $MemoryMB = 8192,

    [Parameter()]
    [int] $Cpus = 4,

    [Parameter()]
    [int] $DiskGB = 80,

    [Parameter()]
    [int] $TimeoutMinutes = 60,

    # Delete a VM of the same name, its disks and snapshots, first.
    [Parameter()]
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StigLab.ps1')

$user = 'ansible'
$snapshot = 'baseline'

if (Get-StigLabVmState -Name $Name) {
    if (-not $Force) {
        throw "VM '$Name' already exists. Use -Force to replace it."
    }

    if ((Get-StigLabVmState -Name $Name) -eq 'running') {
        Invoke-VBoxManage controlvm $Name poweroff | Out-Null
        Start-Sleep -Seconds 3
    }

    $folder = Split-Path (Get-StigLabVmInfo -Name $Name).CfgFile
    # --delete, not --delete-all: the latter also deletes the install ISO.
    Invoke-VBoxManage unregistervm $Name --delete | Out-Null
    Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
}

$alphabet = [char[]] 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
$password = (-join (1..20 | ForEach-Object {
    $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32($alphabet.Count)]
})) + '-Aa9'

# Saved before the install, so a build that fails part-way still leaves the guest reachable.
$state = [ordered] @{
    Name      = $Name
    IPAddress = $IPAddress
    User      = $user
    Password  = $password
    Snapshot  = $snapshot
}
$state | ConvertTo-Json | Set-Content -Path (Get-StigLabStatePath -Name $Name -ChildPath 'vm.json')

Invoke-VBoxManage createvm --name $Name --ostype Windows2022_64 --register | Out-Null
Invoke-VBoxManage modifyvm $Name --cpus $Cpus --memory $MemoryMB --vram 128 --firmware efi `
    --graphicscontroller vboxsvga --nic1 nat --nic2 hostonly --hostonlyadapter2 $HostOnlyAdapter | Out-Null

$info = Get-StigLabVmInfo -Name $Name
$disk = Join-Path (Split-Path $info.CfgFile) "$Name.vdi"
Invoke-VBoxManage createmedium disk --filename $disk --size ($DiskGB * 1024) --format VDI | Out-Null
Invoke-VBoxManage storagectl $Name --name SATA --add sata --controller IntelAhci --portcount 4 | Out-Null
Invoke-VBoxManage storageattach $Name --storagectl SATA --port 0 --device 0 --type hdd --medium $disk | Out-Null

# Windows names a MAC 08-00-27-..., VirtualBox 080027...
$mac = ($info.macaddress2 -split '(..)' -ne '') -join '-'

# The bootstrap travels as -EncodedCommand: the post-install command is one line of a .cmd file.
$bootstrap = (Get-Content -Path (Join-Path $PSScriptRoot 'Initialize-StigLabGuest.ps1') -Raw) -replace
    '(?s)<#.*?#>' -replace '(?m)^\s*#.*\r?\n'
$command = "& {`n$bootstrap`n} -MacAddress '$mac' -IPAddress '$IPAddress'"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

Invoke-VBoxManage unattended install $Name "--iso=$IsoPath" "--image-index=$ImageIndex" `
    "--user=$user" "--password=$password" "--full-user-name=$user" "--key=$ProductKey" `
    --install-additions "--hostname=$Name.stig.lab" --time-zone=UTC `
    "--post-install-command=powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" `
    --start-vm=headless | Out-Null

Write-Verbose "Installing Windows on $Name; the guest powers itself off when the bootstrap succeeds."
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ((Get-StigLabVmState -Name $Name) -ne 'poweroff') {
    if ((Get-Date) -gt $deadline) {
        throw "$Name did not finish bootstrapping within $TimeoutMinutes minutes. See C:\stiglab-bootstrap.log in the guest."
    }
    Start-Sleep -Seconds 30
}

# Drop the install media so the baseline does not depend on the ISO staying where it is.
foreach ($port in 1..3) {
    if ((Get-StigLabVmInfo -Name $Name)."SATA-$port-0" -notin $null, 'none') {
        Invoke-VBoxManage storageattach $Name --storagectl SATA --port $port --device 0 --medium none | Out-Null
    }
}

Invoke-VBoxManage snapshot $Name take $snapshot --description 'Windows installed and bootstrapped, nothing applied' | Out-Null

[pscustomobject] $state | Select-Object -Property * -ExcludeProperty Password
