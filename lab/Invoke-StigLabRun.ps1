<#
.SYNOPSIS
    Applies freshly generated roles to a lab VM restored to its baseline.

.DESCRIPTION
    Builds the module if it is stale, generates a role per STIG, restores the VM New-StigLabVm
    built to its baseline snapshot, waits for WinRM and runs the play from WSL's Ansible.
    Roles, inventory and the Ansible log land in lab/.local/<Name>/runs/<timestamp>.

    By default every task runs even after one fails or the host stops answering, so one run
    surveys the whole role, and each failure is listed in failures.csv beside the log. A failed
    organization-value assert then no longer stops the task it guards, so that task fails too.
    -StopOnFailure stops at the first failure instead.

    The VM is left running so it can be inspected.

.EXAMPLE
    ./lab/Invoke-StigLabRun.ps1 -Name stig-ws2025 -StigName WindowsServer-2025-MS
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $Name,

    [Parameter(Mandatory)]
    [string[]] $StigName,

    # Where Copy-PowerStigFile put the STIG data, if not the default.
    [Parameter()]
    [string] $Path,

    [Parameter()]
    [switch] $AllowIncompleteOrganizationValue,

    # Passed to ansible-playbook --tags, e.g. cat1.
    [Parameter()]
    [string[]] $Tags,

    [Parameter()]
    [switch] $StopOnFailure,

    [Parameter()]
    [int] $TimeoutMinutes = 15
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StigLab.ps1')

$stateFile = Get-StigLabStatePath -Name $Name -ChildPath 'vm.json'
if (-not (Test-Path $stateFile)) {
    throw "No lab state for '$Name'. Build the VM with New-StigLabVm.ps1 first."
}
$vm = Get-Content -Path $stateFile -Raw | ConvertFrom-Json

$stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
$run = Get-StigLabStatePath -Name $Name -ChildPath "runs\$stamp"
New-Item -Path $run -ItemType Directory -Force | Out-Null
$roles = Join-Path $run 'roles'

# Generate before touching the VM, so a conversion that refuses costs nothing.
. (Join-Path $PSScriptRoot '..\tests\Initialize-TestModule.ps1')
$generate = @{ OutputPath = $roles; AllowIncompleteOrganizationValue = $AllowIncompleteOrganizationValue }
if ($Path) { $generate.Path = $Path }
foreach ($stig in $StigName) {
    New-AnsiblePlaybook -StigName $stig @generate
}
$roleNames = (Get-ChildItem -Path $roles -Directory).Name

@"
all:
  hosts:
    $($vm.Name):
      ansible_host: $($vm.IPAddress)
  vars:
    ansible_connection: winrm
    ansible_port: 5985
    ansible_winrm_transport: ntlm
    ansible_winrm_scheme: http
    # Applying a user right or security option can stall the guest past the 30s default.
    ansible_winrm_operation_timeout_sec: 120
    ansible_winrm_read_timeout_sec: 150
    ansible_user: $($vm.User)
    ansible_password: '$($vm.Password)'
"@ | Set-Content -Path (Join-Path $run 'inventory.yml')

@"
- name: Apply the generated STIG roles
  hosts: all
  ignore_errors: $(([string] (-not $StopOnFailure)).ToLower())
  ignore_unreachable: $(([string] (-not $StopOnFailure)).ToLower())
  roles:
$(($roleNames | ForEach-Object { "    - $_" }) -join "`n")
"@ | Set-Content -Path (Join-Path $run 'site.yml')

@"
[defaults]
inventory = inventory.yml
roles_path = roles
log_path = ansible.log
host_key_checking = False
callback_result_format = yaml
"@ | Set-Content -Path (Join-Path $run 'ansible.cfg')

if ((Get-StigLabVmState -Name $Name) -eq 'running') {
    Invoke-VBoxManage controlvm $Name poweroff | Out-Null
    while ((Get-StigLabVmState -Name $Name) -ne 'poweroff') { Start-Sleep -Seconds 2 }
}
Invoke-VBoxManage snapshot $Name restore $vm.Snapshot | Out-Null
Invoke-VBoxManage startvm $Name --type headless | Out-Null

# Ansible runs from a copy in WSL's own filesystem; see New-StigLabWslDirectory.
$workspace = New-StigLabWslDirectory -ChildPath "$Name/$stamp"
Copy-Item -Path "$run\*" -Destination $workspace.Windows -Recurse
$ansible = "cd '$($workspace.Wsl)' &&"

Write-Verbose "Waiting for WinRM on $($vm.IPAddress)."
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
do {
    if ((Get-Date) -gt $deadline) {
        throw "$Name did not answer win_ping within $TimeoutMinutes minutes. Last attempt:`n$($ping -join "`n")"
    }
    Start-Sleep -Seconds 15
    $ping = Invoke-StigLabWsl "$ansible ansible all -m ansible.windows.win_ping" 2>&1 | Select-Object -Last 10
} until ($LASTEXITCODE -eq 0)

$playbook = "$ansible ansible-playbook site.yml"
if ($Tags) { $playbook += " --tags $($Tags -join ',')" }
Invoke-StigLabWsl $playbook | Out-Host
$exitCode = $LASTEXITCODE
Copy-Item -Path (Join-Path $workspace.Windows 'ansible.log') -Destination $run -ErrorAction SilentlyContinue

# Each failed task with the first line of its message, read back out of the log.
$failures = [System.Collections.Generic.List[object]]::new()
$task = $pending = $null
foreach ($line in Get-Content -Path (Join-Path $run 'ansible.log') -ErrorAction SilentlyContinue) {
    if ($line -match 'TASK \[(?<task>.+?)\]') { $task = $Matches.task }
    elseif ($line -match '(fatal|failed): \[|UNREACHABLE!') { $pending = $task }
    elseif ($pending -and $line -match '\smsg: (?<msg>.+)') {
        $failures.Add([pscustomobject] @{ Task = $pending; Message = $Matches.msg.Trim("' ") })
        $pending = $null
    }
}
$failures | Export-Csv -Path (Join-Path $run 'failures.csv') -NoTypeInformation

[pscustomobject] @{
    Name     = $Name
    Roles    = $roleNames
    RunPath  = $run
    Failed   = $failures.Count
    ExitCode = $exitCode
}
