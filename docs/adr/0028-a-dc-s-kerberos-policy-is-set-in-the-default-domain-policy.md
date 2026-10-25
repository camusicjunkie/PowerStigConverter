---
status: accepted
---

# A DC's Kerberos policy is set in the Default Domain Policy

The 2025 DC STIG checks five Kerberos policy values "in the Default Domain Policy": V-278133,
*Enforce user logon restrictions*, and the four lifetimes V-278134–V-278137. The role wrote them
locally with `win_security_policy`, as it does `[System Access]`. On a DC that write does not take.
In the lab, a local secedit write of `TicketValidateClient = 0` changed neither the DC's own
export nor the Default Domain Policy's template, before or after `gpupdate /force`. The tasks
reported `ok` only because the lab's values equal the Windows defaults. A stricter organization
value would have been written each run, had no effect, and reported `changed`.

`[System Access]` differs: on a DC a local secedit write is the domain's policy and is written into
the Default Domain Policy (ADR 0027).

## Decision

**On a DC, each `[Kerberos Policy]` rule sets its key in the Default Domain Policy's
`GptTmpl.inf`.** The task runs `Source/Files/Set-DefaultDomainPolicyValue.ps1`:

- It finds the GPO by its fixed GUID, `{31B2F340-016D-11D2-945F-00C04FB984F9}`, under the DC's own
  SYSVOL, not by its display name, which can be changed.
- It reads before it writes. When the template already holds the value, nothing is written and the
  task reports no change.
- When it writes, it raises the GPO's computer version on the AD object and in `GPT.INI`, as GPMC
  does, so clients apply the change.
- Under check mode it reports and writes nothing.

The value is the rule's organization value, as before; its `defaults/` variable is the value
written.

**V-278133 converts** through a `HardCodedRule` correction (ADR 0020), since PowerStig's 4.30.0
`.log` forces it to a ManualRule.

## Alternatives considered

**Report only, leaving the Kerberos defaults in place.** The defaults already meet DISA's bounds,
and it avoids editing a default policy. Rejected: where Ansible is the only thing applying the
STIG, nothing else will ever set a stricter value.

**Skip Kerberos policy on a DC**, as ansible-lockdown does for account policy on any domain-joined
host. Rejected for the same reason.

## Consequences

- A DC role edits the Default Domain Policy, as ADR 0027 already has it do for `[System Access]`.
  Each rule's `_when` toggle is the opt-out for an organization that manages the policy by hand.
- The script is shipped as task text and tested by running it against a SYSVOL tree in
  `TestDrive`, so a change to it is caught without a DC.

Decided in [#234](https://github.com/camusicjunkie/PowerStigConverter/issues/234).
