---
status: accepted
---

# Linux role scaffolding selects on OS family, and become lives in the adapter

The role scaffolding assumed a Windows target in three places: `Source/Roles/main_task.yml`
asserted `ansible_os_family == 'Windows'` and set a Server Core fact from
`ansible_os_installation_type`, a fact that does not exist on Linux; `Source/Roles/main_handler.yml`
hard-coded an `ansible.windows.win_reboot` handler. All three block a Linux role from running.
[ADR 0006](0006-a-linux-task-escalates-but-carries-no-identity.md) also left one question open:
where `become: true` gets attached, since `ConvertTo-AnsibleTask` is rule-type agnostic and must
not start branching on rule type.

## Decision

**Template selection.** `Get-AnsibleOsAssertion` — already the one place that reads a STIG name and
decides how the role asserts against it — grows two more properties: `OsFamily` (the literal
`ansible_os_family` value, `Windows` or `RedHat`) and `OsMajorVersion`. Both become new Plaster
parameters. `Roles/` gains `main_task_linux.yml`, `main_handler_linux.yml` and
`main_default_linux.yml` beside their Windows counterparts, each pair mutually exclusive via
Plaster's native `condition` attribute keyed on `OsFamily`. One manifest, one `TemplatePath`; no
second directory for `New-AnsibleRoleScaffold` to choose between.

**The Linux assert checks family and major version, not distribution name alone.** Windows's
existing assert gets away with a single `ansible_distribution` regex because the fact already bakes
in the version (`"Microsoft Windows Server 2022 Datacenter"`). Linux's `ansible_distribution` is
just `RedHat` or `OracleLinux` — OracleLinux-8 and OracleLinux-9 both report the same value. The
Linux assert therefore also checks `ansible_distribution_major_version == '<OsMajorVersion>'`, or
it cannot tell those two apart and stops guarding anything.

**No Server Core fact, no `win_reboot` handler on Linux.** Omitted, not stubbed: Linux has no
Server Core concept, and no in-scope rule notifies a reboot handler.

**`become: true` is set inside the adapter, never a credential.** `Build-AnsibleNxFileLineTask` and
`Build-AnsibleNxServiceTask` each add `'become' = $true` to their own `Body` hashtable —
`ConvertTo-AnsibleTask` merges `Body` onto the task verbatim already, so this needed no new
machinery in it or in any role template. This settles ADR 0006's open question.

## Alternatives considered

**Two template directories, selected in PowerShell before calling `Invoke-Plaster`.** Rejected:
Plaster's `condition` attribute already selects content conditionally at the file level, so a
second `TemplatePath` would only be a second thing to keep in sync with the first.

**Attach `become` at the role-template level**, relying on Ansible's keyword-inheritance from an
`import_tasks` step. Rejected: the adapter already owns everything that differs by rule type, and
setting the key there needed nothing new — no template change, no new keyword to reason about at
the play level.

**Scaffold an empty reboot handler for parity with Windows.** Rejected: no in-scope Linux rule
notifies one. Speculative machinery this repo's style avoids; add it the day a rule needs it.

## Consequences

- A fourth Linux product is one more `switch` arm in `Get-AnsibleOsAssertion`, not a new file.
- `OsMajorVersion` exists as a Plaster parameter but is unused by the Windows templates.
- The Windows templates and `ConvertTo-AnsibleTask` are unchanged by this decision.

Decided in [#79](https://github.com/camusicjunkie/PowerStigConverter/issues/79).
