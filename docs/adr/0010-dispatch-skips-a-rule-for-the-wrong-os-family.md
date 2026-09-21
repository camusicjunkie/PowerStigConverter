---
status: accepted
---

# Dispatch skips a rule for the wrong OS family, rather than building it anyway

`ConvertTo-AnsiblePlaybook` routes a rule to its adapter on rule-type name alone
(`Get-Command "Build-Ansible$($ruleName)Task"`), a match that predates this module having more
than one `OsFamily` to target. It carries no notion of which `OsFamily` the adapter it just found
actually targets.

This was silent until the Linux STIGs, because every adapter agreed on `OsFamily` by construction
- all twenty were Windows-only. It stopped being silent by accident rather than by design:
`OracleLinux-9-1.1`'s fixture (see #86) carries a `PermissionRule`, the same rule-type name the
Windows-only `Build-AnsiblePermissionTask` already owns (emitting `ansible.windows.win_acl`).
Today it converts to nothing only because the rule is unparsed
(`dscresource="None"`, an empty `AccessControlEntry`) - a fact about the current data, not a check
dispatch performs. The moment upstream PowerStig parses a Linux `PermissionRule` successfully -
exactly the kind of revision-over-revision improvement `CONTEXT.md`'s "unparsed rule" entry and
ADR 0009 both already describe happening - dispatch would route it straight into the Windows-only
adapter, and a `RedHat`-asserted role would get a task requiring `ansible.windows.win_acl`.

## Decision

**A new table, one entry per adapter.** `Source/Files/RuleTypeOsFamily.psd1` names the
`OsFamily` each rule type's adapter targets (`'Windows'` for all twenty pre-existing adapters,
`'RedHat'` for `nxFileLine` and `nxService`), loaded into `$script:ruleTypeOsFamily` in
`Source/prefix.ps1` - the same shape `OrganizationData.psd1` and `RoleVariableData.psd1` already
use: one function, or here one dispatcher, answers the question from one file, rather than the
fact living split across 22 adapter bodies.

**Dispatch reads its own `OsFamily` once, from the STIG name it was already given.**
`Get-AnsibleOsAssertion -StigName $StigName` is the same pure, cheap lookup
`New-AnsibleRoleScaffold` already calls for the role's own assert (ADR 0007) - dispatch calls it
independently rather than threading the scaffold's answer through, since it already has
`$StigName` and needs nothing else the scaffold computes.

**A mismatch is skipped and warned, not a hard error.** `ConvertTo-AnsiblePlaybook` already has
exactly one failure mode per rule - no adapter found, warn and move on - and an `OsFamily`
mismatch is the same shape of fact ("no *usable* adapter for this rule"), not a new severity.
This also matches `Build-AnsibleNxFileLineTask`'s own skip-and-warn precedent (ADR 0009) for a
rule its adapter cannot honor. A hard error would make an `OsFamily` mismatch the only per-rule
condition in the module that aborts the whole role, which nothing else in dispatch does.

**A rule type missing from the table is not restricted to any `OsFamily`.** The real enforcement
is `GeneratorCoverage.Tests.ps1`, which now fails the suite if a generator has no entry - the
same mechanism it already uses to require a test file and contract coverage. The runtime fallback
only matters when the suite hasn't run at all, and failing safe (warn on a genuine mismatch, stay
silent on an incomplete table) is less surprising than a table gap silently discarding every rule
of some already-working rule type.

## Alternatives considered

**Infer `OsFamily` from the `Nx`-prefixed function name.** Rejected: `CONTEXT.md`'s own notes
already call this naming cosmetic, kept only because PowerShell function resolution is
case-insensitive. Making it load-bearing would tie a real safety check to a spelling convention.

**Each adapter takes an `-OsFamily` parameter and asserts it matches.** Rejected: touches all 22
existing adapters for one new, unrelated concern - the kind of scattered edit `ConvertTo-AnsibleTask`
already exists to avoid ("nothing here branches on rule type; if it ever needs to, the adapter
contract is the thing that is wrong").

**Hard error on mismatch**, matching `New-AnsiblePlaybook`'s refusal to write a role with an
incomplete organization value. Rejected: that refusal exists because an unanswered policy question
is silently wrong in a way nothing downstream can catch; a mismatched adapter is caught right here,
at dispatch, the same as "no adapter" already is.

## Consequences

- `CONTEXT.md`'s "Task generator" entry now distinguishes two reasons a rule type produces
  nothing: no adapter exists for it at all, or an adapter exists but not for this conversion's
  `OsFamily`.
- A future third `OsFamily` (or a genuinely Linux-targeted `Permission` adapter) is one more
  table entry and one more adapter, not a change to dispatch itself.
- `RuleTypeOsFamily.psd1` is data this module owns and must keep complete - the coverage test
  will not build without it, the same posture already adopted for `OrganizationData.psd1`.

Decided during an architecture review following the Linux STIG map (#78).
