---
status: accepted
---

# An unanswered organization value fails the conversion

PowerStig ships some `OrganizationalSetting` values blank on purpose: they are policy questions
only the adopting organization can answer. Converting with them still blank previously produced
a role anyway — four rule types emitted a task with an empty value, `RootCertificate` dropped
its rule entirely, and both only wrote a warning. Either outcome is a silent compliance gap: a
role that sets the wrong value, or one that quietly omits a STIG requirement.

We now treat an unanswered setting as what it is — an outstanding decision, not a data error —
and refuse to generate. `New-AnsiblePlaybook` collects every gap and throws once, naming all of
them, so a half-filled org settings file can never quietly produce a role.
`-AllowIncompleteOrganizationValue` opts out for people iterating, and ADR-0003 governs what
that produces.

## Considered options

- **Skip the rule** (generalising `RootCertificate`) — rejected: a dropped STIG rule is invisible
  in the generated role, which is the worse of the two failure modes it would standardise on.
- **Emit a placeholder and warn** — rejected as the default: warnings scroll past, and the role
  looks finished.

## Consequences

A **missing setting** and an **unanswered setting** are reported as distinct faults with distinct
messages, because their remedies differ: fill in the value, versus fetch an org settings file
matching your STIG version. Collapsing them would make a version mismatch present as hundreds of
unanswered questions.
