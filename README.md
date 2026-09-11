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
- [`Plaster`](https://www.powershellgallery.com/packages/Plaster) — scaffolds the role directories

Both are declared in the module manifest, so `Import-Module` will not load
PowerSTIGConverter without them.

```powershell
Install-Module -Name powershell-yaml, Plaster -Scope CurrentUser
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

A complete Ansible role is created in the current directory, named after the STIG. Use
`-OutputPath` to build it somewhere else and `-RoleName` to name it yourself; the directory is
created if it does not exist.

```powershell
New-AnsiblePlaybook -StigName WindowsServer-2022-MS -OutputPath .\roles -RoleName stig_2022_ms
```

## What it generates

```
<RoleName>/
  tasks/
    main.yml                 asserts the OS, imports each severity file by tag
    cat1.yml                 generated
    cat2.yml                 generated
    cat3.yml                 generated
  defaults/main/
    main.yml                 hand-editable defaults
    main_default_cat1.yml    generated
    main_default_cat2.yml    generated
    main_default_cat3.yml    generated
    main_default_org.yml     generated
  vars/main.yml
  handlers/main.yml
```

Re-running is safe. The generated files are replaced every run; the four scaffolding files are
written once and never overwritten, so edits to them survive.

Tasks are split by rule severity, matching the DISA category system:

| File | Severity | DISA category |
| --- | --- | --- |
| `cat1.yml` | high | CAT I |
| `cat2.yml` | medium | CAT II |
| `cat3.yml` | low | CAT III |

Alongside these, the module emits the variables the tasks depend on: organisation-specific values
that a STIG leaves for the implementing site to decide, and conditional values that vary by host.

Every organisation value reaches the role as a variable in `main_default_org.yml`, one per field
the task consumes, which the task interpolates rather than inlining. Answering a question the STIG
leaves open is therefore a one-line edit to that file, not a regeneration.

DISA leaves some of those values blank on purpose, and PowerStig ships them that way. Converting
a STIG whose org settings file still has an unanswered value **fails**, naming every one of them,
rather than producing a role that sets an empty value or silently drops the rule:

```powershell
New-AnsiblePlaybook -StigName WindowsServer-2022-MS
# The organization settings for 'WindowsServer-2022-MS' do not answer every value the role needs
# (2 unanswered).
#
#   V-63321  AccountPolicy   PolicyValue: left blank for the organization to decide
#   V-63323  UserRight       Identity: left blank for the organization to decide
```

A rule the org settings file has no entry for at all is reported separately, because that usually
means the file does not match the STIG version in hand rather than that anything needs filling in.

`-AllowIncompleteOrganizationValue` generates anyway, for iterating on a part-filled org settings
file. The unanswered values are declared blank in `main_default_org.yml` and each one gains an
`ansible.builtin.assert` in the role, so an unfilled value fails the play instead of quietly
configuring nothing. Those asserts are only generated for values that were unanswered at
generation time, and disappear when the role is regenerated against a filled-in file.
`Source/Roles/` holds the scaffolding as a [Plaster](https://github.com/PowerShell/Plaster)
template, which `New-AnsiblePlaybook` runs to lay out the role directories before writing anything
into them. `main_task.yml` becomes `tasks/main.yml`: it asserts the target OS, sets a Server Core
fact, and imports each severity file behind its own `cat1`/`cat2`/`cat3` tag.

Every variable in the role is named from a prefix derived from the STIG — `WindowsServer-2022-MS`
gives `stig_server_2022`, `WindowsClient-11` gives `stig_client_11`. The scaffolding takes that
prefix as the `VariablePrefix` plaster parameter, so the generated files and the hand-written
scaffolding always agree on the names.

The OS assertion in `tasks/main.yml` is derived the same way, matched against
`ansible_distribution`:

| STIG | asserts |
| --- | --- |
| `WindowsServer-2022-MS` | `Microsoft Windows Server 2022` |
| `WindowsServer-2012R2-DC` | `Microsoft Windows Server 2012 R2` |
| `WindowsClient-11` | `Microsoft Windows 11` |
| application STIGs (IIS, SQL Server, .NET) | `Microsoft Windows` |

Application STIGs are not tied to one Windows release, so they assert only that the host is
Windows.

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

## Tests

The suite runs on [Pester](https://pester.dev/) 6.2.0 or later — 6.2.0 is the first release
carrying the whole `Should-*` assertion family the tests use.

```powershell
Install-Module -Name Pester -MinimumVersion 6.2.0 -Scope CurrentUser -SkipPublisherCheck

./Invoke-Tests.ps1
```

The runner builds the module from `Source` and runs the tests against the build output, so what
is tested is what ships. The build is skipped when it is already newer than every source file.

```powershell
./Invoke-Tests.ps1 -Defects            # only the known-defect tests
./Invoke-Tests.ps1 -All                # everything, defects included
./Invoke-Tests.ps1 -CodeCoverage       # writes build/coverage.xml
./Invoke-Tests.ps1 -CI                 # writes build/testResults.xml, exits non-zero on failure
```

Tests live in `tests/`, one file per function under test, and read from hand-written STIG
fixtures in `tests/fixtures/` rather than from downloaded PowerStig data — so they are
deterministic and run on a machine that has never run `Copy-PowerStigFile`.

A test for a defect that has not been fixed yet should be tagged `KnownDefect`, which excludes
it from the default run. There are none at present, so a clean run currently means what it
says. As a defect is fixed its test moves into the file for the function it belongs to and
loses the tag.

## Roadmap

- Error handling and relative-path support in `Copy-PowerStigFile`
- Cover the remaining task generators with tests: `MimeType`, `Permission`, `RootCertificate`
  and `WebConfigurationProperty` are the bulk of the uncovered code
- `New-AnsibleRootCertificateTask` discards the `LocalMachine` segment of a certificate store
  path and relies on `win_certificate_info`'s `store_location` default
- `New-AnsibleServiceTask` and `New-AnsibleRootCertificateTask` name their `register:` from a
  hardcoded `server_2022_stig_` prefix rather than deriving it from the STIG

## Authors and acknowledgment

John Steele

Built on the parsed STIG data published by the [PowerStig](https://github.com/microsoft/PowerStig/)
project at Microsoft.

## License

[MIT](LICENSE)
