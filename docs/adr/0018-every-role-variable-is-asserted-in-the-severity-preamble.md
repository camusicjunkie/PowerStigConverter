---
status: accepted
---

# Every role variable is asserted in the severity-file preamble

A per-rule role variable (`prefix_<id>_<name>`, today the IIS log path) is declared blank for the
site to fill in. Left unasserted, a blank one configures logging with an empty path and the run
reports success: the silent no-op ADR-0001 refuses for organization values. Role-scoped variables
(`websites`, `webapppools`, `instances`) were already asserted non-empty for this reason.

Every role variable is now asserted non-empty, per-rule ones included. The assert is built once in
`Get-AnsibleRuleVariable`, so a future per-rule variable is asserted by default, and it goes in
the severity-file preamble with the role-scoped ones, from the same builder: `length > 0` and the
same message.

It is a run-time assert, not a conversion-time refusal as ADR-0001 uses. The value describes the
site's own machines, so there is nothing at conversion time to check it against.

## Considered options

- **Wrap the rule's own task, as `Add-AnsibleOrganizationValueAssert` does** — rejected: a blank
  value would stop the play partway through a severity file, after earlier rules had already
  changed the host. It also needs a new wrapping step, since per-rule role variables do not pass
  through `Resolve-AnsibleOrganizationValue`.
- **Declare no default, so ansible fails on the undefined variable** — rejected: a worse message,
  and a variable that is not in `defaults/` is harder for the site to find.
- **Leave it blank and unasserted** — rejected: the silent no-op above.

## Consequences

- A blank per-rule variable fails the whole severity file before any of its tasks run, including
  rules unrelated to it. The message names the variable, which is the cost accepted for failing
  before anything is applied.
- Generated output changes for any role with an IIS log path rule; regenerate to pick it up.
- A stricter check (`trim`, a path shape) is a separate decision, and would apply to both kinds
  of role variable from the one builder.
