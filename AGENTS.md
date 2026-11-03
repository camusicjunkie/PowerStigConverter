# PowerStigConverter

Converts Microsoft PowerStig's processed STIG XML data into Ansible roles.

## Build and test

The module is laid out as source under `Source/` and assembled with
[ModuleBuilder](https://github.com/PoshCode/ModuleBuilder); `Source/build.psd1` is the build
configuration and the output lands in `build/PowerStigConverter/<version>/` (gitignored).
`build.ps1` drives [InvokeBuild](https://github.com/nightroman/Invoke-Build) tasks defined in
`PowerStigConverter.build.ps1`; [PSDepend](https://github.com/RamblingCookieMonster/PSDepend)
installs what `PowerStigConverter.depend.psd1` lists into `build/modules`.

```powershell
./build.ps1 -ResolveDependency -Task Noop                          # first time: dependencies
./build.ps1 -Task QuickTest                                        # build at 0.0.0, run the suite
./build.ps1 -Task QuickTest -TestPath ./tests/Get-PowerStigFile.Tests.ps1
./build.ps1 -Task Defects                                          # only the known-defect tests
./build.ps1                                                        # Clean, Analyze, Build, Test
```

`Build` and the default task version the module with [GitVersion](https://gitversion.net), which
must be on `PATH`; `DevBuild` and `QuickTest` build at `0.0.0` without it. `Analyze` runs
PSScriptAnalyzer over `Source/Public`, `Source/Private` and `prefix.ps1`, and on PowerShell 7 with
Windows PowerShell beside it also checks that 5.1 can parse every script.

Requires `powershell-yaml` and `Plaster` at runtime (both declared in the manifest), plus
`ModuleBuilder` and `InvokeBuild` to build and `Pester` 6.2.0+ to test; the depend file covers
all of them. `git` must be on `PATH` for `Copy-PowerStigFile`.

CI runs Analyze, Build and Test under both PowerShell 7 and Windows PowerShell 5.1. A branch with
an open PR is not done until `gh pr checks` is green. Pushing a `vX.Y.Z` tag on `main` runs
`.github/workflows/release.yml`, which publishes that version to the PowerShell Gallery (secret
`NUGET_API_KEY`) and creates the GitHub release.

The manifest in `Source/` keeps `ModuleVersion` at `0.0.0` and the export lists empty: the build
sets the version and fills the exports from `Source/Public`. Do not edit them by hand.

Tests import the **built** module, not `Source/*.ps1`, which is what lets `InModuleScope` reach
the private functions and reproduces the script-scope data `Source/prefix.ps1` sets up. Code
coverage has to be measured over the build output for the same reason — pointed at `Source/` it
reports 0%. `tests/Initialize-TestModule.ps1` builds the module itself when there is no build
or the build is older than `Source/`, so a single test file can still be run with bare `Invoke-Pester`.

Tests tagged `KnownDefect` are excluded by default and are expected to fail; none exist at
present. Tag a test that way when it describes a defect you are not fixing in that pass, and
untag it when the defect is fixed.

Every task generator has a test file of its own that calls `Add-GeneratorContractTests` from
`tests/GeneratorContract.ps1` — the cases that are the same for every rule type, plus two that
apply conditionally. `tests/GeneratorCoverage.Tests.ps1` reads the generators off disk and fails
the suite if one has no test file, does not call the contract, or skips the list-shape or
organization-value case where its rule type needs it. Adding a rule type therefore means adding
a test file; the contract file itself says what that file has to cover.

Task generators do not modify the rule they were handed, so the same rule object can go through
one twice. Tests still build a fresh rule per case, so a failure cannot be an artefact of a
previous case's leftovers.

A task generator reads the rule and nothing else — never the converting machine's filesystem,
environment or registry, since that is not the machine the rule describes. See `docs/adr/0005`.

Organisation values — the ones a STIG leaves for the adopting organisation to decide — reach the
generated role as variables in `defaults/`, never as literals. `New-AnsiblePlaybook` refuses to
convert while any of them is unanswered; `-AllowIncompleteOrganizationValue` overrides that. See
`CONTEXT.md` for the vocabulary and `docs/adr/0001`–`0003` for why.

Every question about a rule's organization values is answered by one function,
`Resolve-AnsibleOrganizationValue` — the value the task consumes, the variables `defaults/`
declares, the ones the org settings file leaves unanswered, and the assert guarding those.
`Resolve-AnsibleOrganizationValue` is the only place that reads a rule type's *fields* out of
`OrganizationData.psd1`; `ConvertTo-AnsibleTask` additionally tests it for membership
(`ContainsKey`) to skip rule types it says nothing about. Both read the file's keys rather than a
copied list, so adding a rule type is one edit in one file. See `docs/adr/0004`.

When PowerStig's data is wrong for a rule (a misparsed principal, a garbled org default), correct
it in `Source/Files/RuleCorrection.psd1`, not with a heuristic in a generator. See `docs/adr/0020`.

Only a rule that produced a task matters to the rest of a conversion. The incomplete-value gate
and the `defaults/` exporter read the converted tasks, never the raw rules, so dispatch is the one
place that decides what gets skipped. See `docs/adr/0016`.

## Live test host

The VirtualBox lab lives in the VmLab module (`D:\PowerShell\Modules\VmLab`), not here. Its
`examples/PowerStigConverter/Invoke-StigLabRun.ps1` restores a VmLab VM to its baseline, generates
roles from this clone and applies them from WSL's Ansible; the lab's answers to blank organization
values (`LabOrganizationValues.psd1`) sit beside it. VM state and run output live under
`%LOCALAPPDATA%\VmLab\<Name>\`. Older runs remain in the gitignored `lab/.local/`, which
`docs/timings/Measure-TaskTiming.ps1` still reads by default.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `camusicjunkie/PowerStigConverter`, via the `gh` CLI.
See `docs/agents/issue-tracker.md`, which includes what a `Closes #n` commit owes its issue's labels.

### Triage labels

The five canonical triage roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root.
See `docs/agents/domain.md`.
