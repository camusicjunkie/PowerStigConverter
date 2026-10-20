---
status: accepted
---

# Long-running is declared per rule type and applied as a tag by dispatch

Lab timings (#179) show a handful of rules, nearly all `Permission` rules on broad roots, take a
third to over half of a full run. An operator should be able to run them separately, for example
as a second, less frequent AAP job template (#181 decided the run-time mechanism: a
`long_running` tag). What remains is where a rule is classified and who stamps the tag.

## Decision

**Classification is by rule type, in a checked-in table.** `Source/Files/RuleTypeRunTime.psd1`
maps every rule type with an adapter to `Default` or `LongRunning`, loaded in `prefix.ps1` like
`RuleTypeOsFamily.psd1`. The table holds the category, not the 60 s cut-off: the cut-off and the
measurements behind it are recorded in #180 and `docs/timings/`. At present `Permission` is the only `LongRunning`
type. A type never timed is listed `Default`, with a comment saying so.

**One function owns the question.** `Resolve-AnsibleRunTime` is the only reader of the table.

**Dispatch stamps the tag.** `ConvertTo-AnsibleTask` / `Merge-AnsibleRequirement` puts
`tags: [long_running]` on the rule's task, or on the outer block of a grouped rule, after the
adapter returns. Adapters neither see nor emit it, so a generator still reads the rule and nothing
else (ADR 0005), and sub-rules of one requirement move together. The `catN` tag is untouched.

**Drift is guarded by completeness.** A test fails when an adapter is missing from the table, as
`GeneratorCoverage.Tests.ps1` does for `RuleTypeOsFamily.psd1`, so a new rule type forces a
choice. Because the key is the rule type, V-id renumbering between STIG revisions no longer
matters. Re-measuring is a human act, recorded by editing the table and #180's numbers; the
timings live in gitignored `lab/.local/`, so no test checks them.

## Alternatives considered

**A plain list of long-running types.** Rejected: a new rule type silently defaults to Default,
with no moment where anyone decides.

**Per-rule (V-id) classification.** Rejected in #180: the type already is the group, and V-ids
renumber between revisions.

**Each adapter adds the tag.** Rejected: the decision would sit in every adapter, and a block built
by dispatch would have to be tagged separately.

**Measuring at convert time.** Rejected: it reads the converting machine, not the one the rule
describes (ADR 0005).
