# Lab

Applies generated roles to a real Windows Server VM, so a role is tested against the host it
describes and not only against fixtures.

## Needs

- VirtualBox, with a host-only adapter on 192.168.56.0/24.
- A Windows Server ISO that supports unattended install.
- WSL with `ansible-core` and the `ansible.windows` and `community.windows` collections.
- The STIG data `Copy-PowerStigFile` fetches.

## Build a VM

```powershell
./lab/New-StigLabVm.ps1 -Name stig-ws2025 -IsoPath D:\LabSources\ISOs\Server2025.iso -IPAddress 192.168.56.25
```

The script installs Windows unattended and runs `Initialize-StigLabGuest.ps1` inside the guest at
first logon. That sets the static address, configures WinRM, and installs `AuditSystemDsc`. The
guest then powers itself off and the script snapshots it as `baseline`. Nothing needs the
console. It takes about 20–30 minutes. `-Force` replaces an existing VM of that name.

## Run

```powershell
./lab/Invoke-StigLabRun.ps1 -Name stig-ws2025 -StigName WindowsServer-2025-MS, WindowsDefender-All, WindowsFirewall-All
```

Every run restores `baseline` first, so runs don't affect each other. The VM is left running
afterwards for inspection.

A run may lose the host part way. The STIG denies local administrators network logon, which
should cut off the WinRM connection Ansible is using, and a slow security policy change can stall
the guest. By default the play carries on and records the host as unreachable. Where the STIG
actually cuts Ansible off has not been observed yet; see #151.

Carrying on has a cost: a failed organization-value assert no longer stops the task it guards, so
that task fails too. Pass `-StopOnFailure` to stop at the first failure instead.

## State

`lab/.local/<Name>/` is gitignored. It holds `vm.json` with the guest's generated password, and
one directory per run under `runs/` with the roles, inventory, and `ansible.log`.

Ansible itself runs from a copy of each run directory at `~/stiglab/<Name>/<run>` inside WSL. WSL
need not mount the drive the repo is on, and it treats the drives it does mount as
world-writable, which makes Ansible ignore `ansible.cfg`. That copy holds the inventory too, so
it also contains the password.
