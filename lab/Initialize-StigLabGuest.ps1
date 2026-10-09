<#
.SYNOPSIS
    Prepares a freshly installed Windows Server guest as an Ansible target.

.DESCRIPTION
    Runs inside the guest. New-StigLabVm hands it to VirtualBox's unattended install as the
    post-install command, which Windows runs at first logon with a full admin token - the only
    point at which nothing outside the guest can elevate.

    On success it schedules a shutdown, which is how the host knows the guest is ready for its
    baseline snapshot. On failure the guest stays up and C:\stiglab-bootstrap.log says why.
#>
[CmdletBinding()]
param (
    # The host-only NIC, in Windows' 08-00-27-AA-BB-CC form.
    [Parameter(Mandatory)]
    [string] $MacAddress,

    [Parameter(Mandatory)]
    [string] $IPAddress,

    [Parameter()]
    [int] $PrefixLength = 24
)

$ErrorActionPreference = 'Stop'
Start-Transcript -Path C:\stiglab-bootstrap.log -Force

# The host-only NIC gets the fixed address the inventory names.
$nic = Get-NetAdapter | Where-Object MacAddress -eq $MacAddress
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null
Rename-NetAdapter -Name $nic.Name -NewName 'HostOnly'

# WinRM over HTTP, NTLM-encrypted; the host-only network never leaves this machine.
Enable-PSRemoting -SkipNetworkProfileCheck -Force
Set-NetFirewallRule -Name WINRM-HTTP-In-TCP -RemoteAddress Any -Profile Any

# A local admin other than the built-in one gets a filtered token over the network without this.
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System `
    -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord

# The DSC resource the generated AuditSetting tasks call through win_dsc.
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name AuditSystemDsc -Scope AllUsers -Force

'BOOTSTRAP-OK'
Stop-Transcript

# Delayed so VirtualBox's own post-install script, which called this one, can finish.
shutdown.exe /s /t 60 /d p:4:1 /c 'stiglab bootstrap complete'
