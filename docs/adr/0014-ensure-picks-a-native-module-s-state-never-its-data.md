---
status: accepted
---

# Ensure picks a native module's state, never its data

A STIG rule's `Ensure` says whether the thing the rule names must exist or must not. PowerStig
writes it on most rule types; upstream carries 206 registry rules with `Ensure=Absent` against 4302
`Present`, spread across 30 processed files — Chrome, Windows Client 10 and 11, Windows Server 2016,
IIS, the Office suite and .NET Framework.

`Build-AnsibleRegistryTask` did not read it. Every rule became a `win_regedit` write, so an `Absent`
rule emitted `data: ''` with `type: none` — which *creates* a REG_NONE value where the STIG says no
value may be present. It failed quietly rather than erroring, and no fixture happened to keep an
`Absent` rule, which is why three maps of Windows coverage went by without catching it. Surfaced by
Defender, the first product where the shape is unavoidable: three of its 67 rules are `Absent`.

The value fields cannot stand in for `Ensure`. Defender's three write `<ValueType>None</ValueType>`
with an empty `<ValueData>`; Chrome's V-245539 writes `<ValueType />` — empty, not `None` — for the
identical intent. Reading them to infer removal means encoding each product's spelling of nothing
and getting it wrong on the next product that invents a third.

## Decision

**`Ensure` chooses the state a task asks a native Ansible module for, and the value-carrying keys
are omitted when it says `Absent`.** For `Registry`: `state: absent` alongside `path` and `name`,
with `data` and `type` gone. Not blank — gone. `name` stays, because it is what keeps `win_regedit`
deleting the value rather than the whole key.

**`Ensure` alone decides.** `ValueType` and `ValueData` are read to fill a `Present` task and are
never consulted to classify one. A rule with no `Ensure` at all takes the `Present` path.

**Where a task targets a DSC resource rather than a native module, `Ensure` passes through
untouched.** `Build-AnsibleSqlDatabaseTask` and `Build-AnsibleMimeTypeTask` hand `Present`/`Absent`
straight to a resource that defines those words itself; translating them there would be inventing a
second vocabulary for one the resource already owns.

**Ensure changes the state key and nothing else.** An `Absent` rule still gets its conditional
toggle, still sorts into a severity file by severity, and still groups with its sub-rules the usual
way.

## Alternatives considered

**Infer removal from the value fields** — no `ValueData`, or a `ValueType` of `None`. Rejected: the
two products that have the shape today already spell it differently, so the condition would be a
growing list of ways to write nothing, maintained by whoever next hits a product that fails
silently.

**Emit `state: absent` but leave `data` and `type` in place as empty strings**, so every registry
task has the same shape. Rejected: the empty pair is precisely the bug — a reader of a generated
role would have to know which keys `win_regedit` ignores under which state to tell a correct task
from the broken one, and a role should not need that knowledge to be read.

**Pass `Ensure` through verbatim to every module, DSC or native**, the way `WindowsFeature` does.
Rejected: the capitalised `Present`/`Absent` is PowerStig's vocabulary, not Ansible's, and a native
module documents its own lowercase choices. `Build-AnsibleWindowsFeatureTask` did exactly this, and
was squared against this decision under
[#117](https://github.com/camusicjunkie/PowerStigConverter/issues/117).

**Treat an `Absent` rule as unconvertible and skip it**, the way a `ManualRule` produces nothing.
Rejected: removing a registry value is something Ansible expresses directly and 206 rules ask for
it, so skipping would drop real remediation on the floor and silently under-cover every product
that has one.

## Consequences

- Chrome, Windows Client 10 and 11, and the other products whose fixtures trimmed their `Absent`
  rules out now convert those rules correctly without their fixtures changing. Only Defender's
  fixture carries the shape end to end; one end-to-end proof is enough, and reaching back into
  closed maps to assert it twice costs review on two maps for one fact.
- `win_regedit`'s other removal mode — deleting a whole key rather than a value — is deliberately
  not reachable. No STIG in the local clone asks for it, and `name` is always present on the rules
  that do ask for removal.
- The DSC/native split is the line to test against when a new rule type reads `Ensure`. It is a
  judgement about which vocabulary owns the word, so a generator that emits both a DSC resource and
  a native module would have to answer it per task rather than per rule type.
- `IsNullOrEmpty`, PowerStig's separate flag for "this value must be an empty string", is untouched
  by this and remains unread. It is a different question — a value that exists and is empty, versus
  a value that must not exist.

Decided in [#111](https://github.com/camusicjunkie/PowerStigConverter/issues/111).
