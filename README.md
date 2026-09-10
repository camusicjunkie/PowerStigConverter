# PowerSTIGConverter

Convert Microsoft's [PowerStig](https://github.com/microsoft/PowerStig/) STIG data into Ansible roles.

## Description

PowerStig is a PowerShell module maintained by Microsoft that automates the application of a
[DISA STIG](https://public.cyber.mil/stigs/) using PowerShell DSC. It ships something valuable
beyond the DSC itself: a set of processed XML files in which every STIG rule has already been
parsed into structured, machine-readable data.

That parsed data is unusable from Ansible, because PowerStig delivers it through DSC composite
resources. This module bridges the gap. It reads PowerStig's processed STIG XML directly and emits
Ansible tasks, variables, and role scaffolding — so the same rule data can drive an Ansible run
instead of a DSC one.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- [`git`](https://git-scm.com/) on `PATH` — used to fetch the PowerStig data files
- [`powershell-yaml`](https://www.powershellgallery.com/packages/powershell-yaml) — provides the
  `ConvertTo-Yaml` command used to serialise tasks

```powershell
Install-Module -Name powershell-yaml -Scope CurrentUser
```

## Installation

The module is laid out as source and assembled with
[ModuleBuilder](https://github.com/PoshCode/ModuleBuilder) — `Source/build.psd1` holds the build
configuration.

```powershell
Install-Module -Name ModuleBuilder -Scope CurrentUser

git clone https://github.com/camusicjunkie/PowerStigConverter.git
cd PowerStigConverter/Source
Build-Module

Import-Module ../build/PowerStigConverter/*/PowerStigConverter.psd1
```

## Usage

### 1. Fetch the PowerStig data

`Copy-PowerStigFile` sparse-clones the processed STIG data out of the PowerStig repository into
`$env:LOCALAPPDATA\PowerStig`. Run it once, and again whenever you want newer STIG releases.

```powershell
Copy-PowerStigFile
```

Pass `-Path` to download somewhere else. Relative paths are resolved against your current
location, and the directory does not need to exist yet.

```powershell
Copy-PowerStigFile -Path D:\stigs
```

### 2. Generate a role

```powershell
New-AnsiblePlaybook -StigName WindowsServer-2022-MS
```

`-StigName` tab-completes from the STIG files you downloaded in step 1. When several versions of a
STIG are present, the highest version is used.

If you gave `Copy-PowerStigFile` a `-Path`, pass the same one here so the STIG data can be found.
Tab completion always reads the default location.

```powershell
New-AnsiblePlaybook -StigName WindowsServer-2022-MS -Path D:\stigs
```

Generated files land in the current directory. Use `-OutputPath` to send them elsewhere; the
directory is created if it does not exist, and each run overwrites the previous one.

```powershell
New-AnsiblePlaybook -StigName WindowsServer-2022-MS -OutputPath .\roles\stig_2022_ms
```

## What it generates

Tasks are written out split by rule severity, matching the DISA category system:

| File | Severity | DISA category |
| --- | --- | --- |
| `cat1.yml` | high | CAT I |
| `cat2.yml` | medium | CAT II |
| `cat3.yml` | low | CAT III |

Alongside these, the module emits the variables the tasks depend on: organisation-specific values
that a STIG leaves for the implementing site to decide, and conditional values that vary by host.
`Source/Roles/` carries the hand-written role scaffolding — `main_task_os.yml` asserts the target
OS, sets a Server Core fact, and imports each severity file behind its own `cat1`/`cat2`/`cat3` tag.

## Supported rule types

Each PowerStig rule type is converted by its own task generator:

| | | |
| --- | --- | --- |
| AccountPolicy | AuditPolicy | AuditSetting |
| IisLogging | MimeType | Permission |
| Registry | RootCertificate | SecurityOption |
| Service | UserRight | WebConfigurationProperty |
| WindowsFeature | | |

A rule type with no matching generator is skipped with a warning rather than failing the run, so
adding support for a new type means adding one `New-Ansible<Type>Task` function.

## Roadmap

- Error handling and relative-path support in `Copy-PowerStigFile`
- Broaden the OS assertion in the role scaffolding beyond Windows Server 2022
- Tests

## Authors and acknowledgment

John Steele

Built on the parsed STIG data published by the [PowerStig](https://github.com/microsoft/PowerStig/)
project at Microsoft.

## License

[MIT](LICENSE)
