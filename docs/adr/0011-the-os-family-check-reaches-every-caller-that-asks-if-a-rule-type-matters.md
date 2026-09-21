---
status: accepted
---

# The OsFamily check reaches every caller that asks whether a rule type matters

ADR 0010 taught `ConvertTo-AnsiblePlaybook` (dispatch) to consult `RuleTypeOsFamily.psd1` before
building a task for a rule type whose name collides across `OsFamily` values. Two more callers
ask a version of the same question - "does this rule type matter for this conversion" - straight
off the raw rule list, by rule-type name alone, blind to `OsFamily`:

- `New-AnsiblePlaybook`'s completeness gate, which runs *before* dispatch produces anything -
  before `New-AnsibleRoleScaffold` puts a role on disk - checking `$script:organizationData.ContainsKey($ruleType)`
  for every rule group and refusing the conversion if any of that group's rules leave an
  organization value unanswered.
- `Export-AnsibleOrganizationValue`, fed the raw `$rules` list (not `$tasks`, the post-dispatch,
  already-`OsFamily`-filtered set every other exporter consumes), checking the same
  `ContainsKey` against `OrganizationData.psd1`/`RoleVariableData.psd1`.

Neither reached by ADR 0010, and both can now disagree with dispatch: a rule type present in
`OrganizationData.psd1` and excluded from this conversion's `OsFamily` would have the completeness
gate refuse (or, under `-AllowIncompleteOrganizationValue`, warn about) a value no task will ever
reference, and the exporter would declare a `defaults/` variable nothing generated references -
the inverse of the orphaned-variable failure mode #57 already closed (there, a reference with no
declaration failed the play; here, a declaration nothing references).

Dormant today, the same way ADR 0010's own trigger was: no rule type in `OrganizationData.psd1`
is also `OsFamily`-mismatched for any in-scope STIG, because real PowerStig data never mixes a
Windows-only rule type into Linux XML or vice versa. But it is the identical shape of bug ADR
0010 closed, one hop upstream of where that ADR looked.

## Decision

**One shared function, all three callers.** `Get-AnsibleRuleTypeOsFamilyMismatch -RuleType -OsFamily`
returns the adapter's own `OsFamily` when it disagrees with the one passed in, or `$null` when it
agrees or the table says nothing about the rule type - the same shape
`Get-AnsibleNxFileLineSkipReason` already uses (ADR 0009): `$null` means proceed, a truthy value
carries the reason. Dispatch, the completeness gate and the exporter all call it instead of each
reading `RuleTypeOsFamily.psd1` for itself - matching this module's existing "one function answers
the question" posture (ADR 0004).

**Dispatch is refactored to call it too**, replacing the inline lookup ADR 0010 added, so the
"one function" story is true for all three rather than two of three. Its warning text and
behaviour are unchanged - the function returns the same value the inline lookup did.

**The completeness gate skips a mismatched rule type's group entirely**, before resolving any of
its rules, the same granularity dispatch already skips at. This can only ever *narrow* what the
gate refuses on; it does not touch the refusal ADR 0001 already guarantees for a genuinely
incomplete value on a rule type that does match this conversion's `OsFamily`.

**The exporter does the same**, per rule-type group, before building any declaration for it.

**Neither of the two new call sites warns on its own skip.** All three run inside one
`New-AnsiblePlaybook` call, in order: completeness gate, then dispatch, then the exporter.
Dispatch already warns once per mismatched rule type, naming every rule id, by the time the
exporter runs - a second and third warning about the same fact would be noise, not new
information. The completeness gate already warns about nothing today, even for a rule type with
no adapter at all; staying silent here is consistent with that existing posture, not a new one.

## Alternatives considered

**Restructure the exporter to consume `$tasks` instead of `$rules`**, matching the other three
exporters. Rejected on inspection: `$tasks` items carry `Rule` (the raw `StigRule`), `Task`,
`Handler` and `RoleVariable`, but no `RuleType` - teaching `ConvertTo-AnsibleTask` to attach one
just to claw back a fact the caller already has would be a larger, more invasive change than
adding the same explicit check dispatch already has. The completeness gate rules this option out
entirely regardless, since it runs before `$tasks` exists.

**Each of the three sites keeps its own inline check.** Rejected: three copies of
`$script:ruleTypeOsFamily[$ruleType]` the moment a second and third caller need it is Duplicated
Code, and this module already has a name for the alternative (ADR 0004).

## Consequences

- A future caller that needs to know whether a rule type applies to this conversion's `OsFamily`
  has one function to call, not a pattern to copy.
- `RuleTypeOsFamily.psd1` and `GeneratorCoverage.Tests.ps1`'s completeness check over it (ADR
  0010) now govern three call sites, not one, without adding another data file or another test.

Decided during an architecture review following ADR 0010.
