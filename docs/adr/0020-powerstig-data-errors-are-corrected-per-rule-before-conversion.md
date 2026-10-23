---
status: accepted
---

# PowerStig data errors are corrected per rule, before conversion

PowerStig's processed data carries parsing errors: `(RX)` read as an account (V-278139, V-254392),
a DC-only `Server Operators` entry in a member-server rule (V-278001.c), identities written as
prose with sentence periods (V-278184), in 2016-MS an org default that is DISA's regex test
string, beside another rule given the wrong rule's list, in Windows 11 a certificate sub-rule
repeating .a's certificate (V-253430.b), and a singular `Enterprise Admin Group` and
`Domain Admin Group` in V-253492 and V-220969. That last is not a PowerStig misparse but DISA's
check-text wording, which a generator now reads (the UserRight split, ADR 0025) and cannot match
to the rule's `Enterprise Admins`. PowerStig fixes its own errors with a `.log` beside each source
STIG (`RuleId::old text::new text`); its 2022 logs remove the same `Server Operators` entry, but its 2025 logs were never given those corrections.

These were first fixed with heuristics in the generators: drop any parenthesised principal, drop
a list of DC-only principals outside a DC, strip periods from an org-valued list. Each guessed at
a pattern from one or two rules and applied it to every rule.

They are now corrected in `Source/Files/RuleCorrection.psd1`, keyed by processed file (revision
included) and rule id, and applied by `Repair-PowerStigData` to the conversion's freshly loaded
data before any generator runs. A correction removes access control entries whose fields match,
or replaces a rule field, or an org setting attribute, while it still holds the value the
correction expects, or replaces a substring of a rule's `RawString` while it occurs there exactly
once. Any field may be named: the expected value, not an allowlist, is what keeps
a correction from overwriting data PowerStig has since fixed. Each carries the reason.

Fixing PowerStig upstream is not part of this: the correction lives here regardless.

## Considered options

- **Heuristics in the generators** — rejected: a generator would guess at bad input from a
  pattern, and the guess applies to rules that never needed it.
- **Leave it to the organization** — rejected: the value is not the organization's to decide;
  the STIG is clear and PowerStig misread it.

## Consequences

- A correction is per revision, so a new revision of a STIG starts with none. When one is
  ingested, check whether the previous revision's corrections still apply.
- A correction that finds nothing to change warns at conversion, and a test applies every
  correction to PowerStig's data where it has been fetched, so a stale one is noticed.
- A generator still builds nothing for a rule a correction leaves with no entry.
- How a correct rule maps onto Ansible on a real host (a wildcard path, a DC's domain lockout
  policy) is not a data error and stays in the generators.
