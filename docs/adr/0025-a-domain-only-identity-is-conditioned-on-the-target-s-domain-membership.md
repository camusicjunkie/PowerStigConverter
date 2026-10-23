---
status: accepted
---

# A domain-only identity is conditioned on the target's domain membership

DISA's user-rights rules list their identities under two headings, `Domain Systems Only:` and
`All Systems:`. PowerStig flattens both into one `Identity`, so V-253491 reaches
`Build-AnsibleUserRightTask` as `Enterprise Admins,Domain Admins,Local account,Guests`. On a
workgroup host `win_user_right` cannot resolve `Enterprise Admins` to a SID, and the task fails as
a whole: `Guests` is not denied either. This is not a PowerStig data error. The STIG makes these
identities depend on the target, so the task decides from the target's facts (ADR 0005), which are
already gathered (ADR 0017).

## Decision

**The generator splits a literal identity list by the rule's `RawString` headings**, and only when
the `RawString` has a `Domain Systems Only:` heading. Each section runs to the next blank line, a
leading `- ` bullet is ignored, and an `Identity` entry, after its sentence period is stripped
(#143), belongs to the section holding a line that starts with it — DISA writes
`Enterprise Admins group` and `Local account (see Note below)`.

**An entry in neither section, or in both, fails the conversion**, naming the STIG and rule. The fix
is a `RuleCorrection.psd1` entry (ADR 0020), which can now replace text in a rule's `RawString`:
V-253492 and V-220969 write `Enterprise Admin Group` for `Enterprise Admins`.

**The task is emitted by the split's shape**, with `action` still taken from `Force`:

- No heading, or no domain-only entries: the literal list, as before.
- Both sections: `users` is the All Systems list plus the domain-only list
  `if ansible_facts['windows_domain_member']`, so the rule always runs.
- Domain-only entries alone: the literal list, with `ansible_facts['windows_domain_member']` ANDed
  after the rule's `_when` toggle in a `when` list. It does not take #143's remove-every-holder
  path, since the STIG does not say no one may hold the right.

**Organization values are untouched.** The split applies only to the literal list a rule carries
itself; a value `Resolve-AnsibleOrganizationValue` reads from org settings is a reference.

## Alternatives considered

**Declare each rule's domain-only identities in `RuleCorrection.psd1`.** Rejected: it needs an entry
per rule per STIG revision, while one parser covers every revision. The headings are DISA's fixed
wording, and a `RawString` that does not account for every entry fails loudly rather than guessing.

**A fixed list of domain-only names** (`Enterprise Admins`, `Domain Admins`). Rejected: domain-only
is a property of the rule, not the name. `Local account` is domain-only on V-253491 and is not by
nature.

**Leave the identities to the organization's list.** Rejected: the STIG fixes them
(`OrganizationValueRequired` is False), so there is no organization value to answer.

## Consequences

- The workgroup lab host exercises the All Systems branch only; unit tests cover the domain branch.
- Privileged Access Workstations, which the STIG exempts from denying Enterprise Admins and Domain
  Admins, are not modelled. An adopter turns the rule off with its `_when` toggle.
- On a domain member, denying network logon to `Local account` cuts a local-account WinRM
  connection. Tracked on #151.

Decided in [#213](https://github.com/camusicjunkie/PowerStigConverter/issues/213).
