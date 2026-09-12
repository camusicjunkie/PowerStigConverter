---
status: accepted
---

# One function answers every organization value question

ADRs 0001–0003 arrived as eight private functions around a single concept: loading the org
settings, finding the values nobody had answered, rendering them for a human, naming a variable,
naming the task the variable is named after, deciding the value that variable is declared with,
building the assert, and wrapping a task in it. Each did a little, and all of them knew the same
four things — the rule, its rule type, the STIG name and the org settings map. That clump
appeared in four signatures, every task generator passed it twice in a row, and
`OrganizationData.psd1` was read from five call sites with its seven keys copied into three
`ValidateSet`s besides.

`Resolve-AnsibleOrganizationValue` now takes those four things once and hands back everything
the rest of the feature asks of them:

| | |
| --- | --- |
| `Value` | what the task consumes — the rule's own value, or a reference to the role variable |
| `Variable` | one organization variable per field, with its name, reference, default and status |
| `Incomplete` | the subset the org settings file does not answer |
| `Assert` | the assert guarding those, or nothing |

A task generator resolves a rule, reads `.Value` into its task and hands the whole resolution to
`Add-AnsibleOrganizationValueAssert`. `New-AnsiblePlaybook` resolves every rule and collects
`.Incomplete`. `Export-AnsibleOrganizationValue` resolves every rule and writes `.Variable`'s
declarations. Four functions where there were eight, and the clump in one signature.

## Consequences

- A rule type's *fields* — what it needs and what each one is called — are read out of
  `OrganizationData.psd1` in one function, so that is one edit in one file. Two callers still
  test the same file for **membership** (`ContainsKey`, to skip rule types it says nothing about),
  which is a different question and stays where the skipping happens. `-RuleType` validates
  against the file's keys rather than a copied `ValidateSet`. All three adapt on their own, so
  adding a rule type needs no second edit.
- The declaration in `defaults/`, the reference the task interpolates and the assert that guards
  it are three properties of the same resolved variable rather than three functions agreeing, so
  they cannot drift apart.
- Tests cross the same seam callers do — the four properties — rather than testing eight
  implementation pieces. The generated role is unchanged: this is a restructuring, and the
  output files are byte for byte what they were.
- **This amends the last paragraph of [ADR-0003](0003-every-organization-value-is-a-role-variable.md),
  which called the IIS log path "a blank organization variable by design".** That contradicts
  `CONTEXT.md`, where an *organization variable* is one holding an organization value, and no org
  settings attribute feeds the log path. It is a role variable the site fills in, not an
  organization variable, so it is no longer handled alongside organization values:
  `Export-AnsibleOrganizationValue` declares it directly, from the same task name
  `New-AnsibleIisLoggingTask` builds its reference from. The generated output is unchanged — it is
  the same variable, declared the same way, under a name the glossary can carry.
- `Get-PowerStigOrgSetting` now fails the way the rest of the feature does — a terminating error
  with an id and a `TargetObject` — rather than with a bare `throw`. See ADR-0002.
