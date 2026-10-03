---
status: accepted
---

# The converted rules are the only answer to whether a rule matters

ADR 0011 put the OsFamily check in front of each of the three callers that ask, in one
`New-AnsiblePlaybook` call, whether a rule matters: the gate that refuses an incomplete
organization value, dispatch, and the organization value exporter. A shared helper kept the check
itself in one place, but each caller still applied its own filters. Dispatch knew whether an
adapter existed and whether it returned `$null`. The gate and the exporter did not. So a rule its
adapter skips, which today means an `nxFileLine` rule under ADR 0009, still declared its
organization variable in `defaults/` and could still make the conversion refuse over a value no
task would ever reference. That is the orphaned declaration ADR 0011 closed for OsFamily,
arriving by a route it did not look at. A rule's organization value was also resolved up to three
times per conversion.

## Decision

**`New-AnsiblePlaybook` converts before it gates, and the gate and the exporter read only the
converted rules.** Converting writes nothing, so the refusal still happens before
`New-AnsibleRoleScaffold` puts anything on disk, as ADR 0002 requires. A rule matters exactly when
it produced a task, so there is nothing left for the gate or the exporter to filter.

**Each converted item carries what its rule leaves for `defaults/`.** `ConvertTo-AnsibleTask` puts
`Declaration` (the organization variables, plus the per-rule role variable `RoleVariableData.psd1`
names) and `Incomplete` on the item beside the task, so the exporter no longer reads rule types,
`OrganizationData.psd1` or `RoleVariableData.psd1`. A block combines these from every sub-rule, and
`Handler` and `RoleVariable` with them, because each sub-rule names its own variables from its own
id, and keeping only the first sub-rule's would drop the rest.

**Dispatch is the only place the OsFamily check happens.** The helper ADR 0011 introduced is
folded back into it, and its skip-and-warn behaviour from ADR 0010 is unchanged.

## Alternatives considered

**A planning step before dispatch** that applies every filter and resolves each rule once.
Rejected: it needs a second way for an adapter to say it would skip a rule, such as a
`Get-Ansible<Type>SkipReason` convention next to every generator. Today an adapter says that by
returning `$null`, and asking the converted rules uses that answer without a new convention.

**Plan only the filters that live outside the adapters.** Rejected: it removes the duplicated
checks but leaves the adapter-skip gap open, which is the bug.

ADR 0011 rejected having the exporter consume `$tasks` for two reasons. Tasks carried no rule type,
and the gate runs before tasks exist. Here the gate runs after conversion, and the tasks carry
the declarations themselves, so the exporter no longer needs a rule type.

## Consequences

- **Supersedes ADR 0011, and amends ADR 0010**: dispatch no longer shares the check with two
  other callers.
- A rule its adapter skips no longer declares its organization variable or refuses the conversion.
  Neither does a rule type `OrganizationData.psd1` describes but no generator handles. None of the
  current fixtures carries either, and all of them generate byte-identical roles.
- The refusal lists incomplete values in the order dispatch emits them: the STIG's order, except
  that a block's sub-rules are listed together where the first of them sits (#125).
- Warnings dispatch raises now come before the gate's refusal rather than after it.
- `Export-AnsibleOrganizationValue` still writes the three severity switches, which have nothing to
  do with organization values. Moving them is a separate change.

Decided in [#121](https://github.com/camusicjunkie/PowerStigConverter/issues/121).
