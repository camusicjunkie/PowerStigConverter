# PowerStigConverter

Converts Microsoft PowerStig's processed STIG XML data into Ansible roles.

## Build and test

The module is laid out as source under `Source/` and assembled with
[ModuleBuilder](https://github.com/PoshCode/ModuleBuilder); `Source/build.psd1` is the build
configuration and the output lands in `build/` (gitignored).

```powershell
Build-Module -SourcePath ./Source/build.psd1     # assemble
./Invoke-Tests.ps1                              # build if stale, then run the suite
./Invoke-Tests.ps1 -Defects                     # only the known-defect tests
./Invoke-Tests.ps1 -CI -CodeCoverage            # pipeline form
```

Requires `powershell-yaml` and `Plaster` at runtime (both declared in the manifest), plus
`ModuleBuilder` to build and `Pester` 6.2.0+ to test. `git` must be on `PATH` for
`Copy-PowerStigFile`.

Tests import the **built** module, not `Source/*.ps1`, which is what lets `InModuleScope` reach
the private functions and reproduces the script-scope data `Source/prefix.ps1` sets up. Code
coverage has to be measured over the build output for the same reason — pointed at `Source/` it
reports 0%.

Tests tagged `KnownDefect` are excluded by default and are expected to fail. A green run means
no regressions, not no known problems.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `camusicjunkie/PowerStigConverter`, via the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root.
See `docs/agents/domain.md`.
