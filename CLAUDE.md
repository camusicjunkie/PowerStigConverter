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
`OrganizationData.psd1`; two callers additionally test it for membership (`ContainsKey`) to skip
rule types it says nothing about. Both adapt on their own, so adding a rule type is one edit in
one file. See `docs/adr/0004`.

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
