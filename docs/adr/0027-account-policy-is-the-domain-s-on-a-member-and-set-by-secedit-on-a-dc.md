---
status: accepted
---

# Account policy is the domain's on a member, and set by secedit on a DC

The Windows 11 role failed V-253297, *Account lockout duration*, on a freshly joined lab member:
`The key 'LockoutDuration' in section 'System Access' is not a valid key`.
`community.windows.win_security_policy` only sets a key `secedit /export` lists, and Windows
lists `LockoutDuration` and `ResetLockoutCount` only while `LockoutBadCount` is above 0. Every
Windows STIG but 2019 lists lockout duration before the threshold, so a host whose threshold
starts at 0 cannot take duration or reset in the order the data gives them.

On a domain member the domain owns `[System Access]`: the member's values came from the Default
Domain Policy, and the threshold task reported `ok` without writing. On a DC the lab showed a local
secedit write *is* the domain's policy: the domain object took it at once, and it was written into
the Default Domain Policy's `GptTmpl.inf`.

## Decision

**The lockout threshold runs first.** `AccountPolicyData.psd1` marks its entry `First`.
`Resolve-AnsibleInfOption` returns the mark, the adapter returns it, dispatch carries it without
reading it, and `Group-AnsibleBySeverity` puts a marked item ahead of the rest of its severity file,
which stay in id order. Dispatch still branches on nothing.

**Outside a DC, account policy runs only off a domain.** A role whose STIG name does not end in
`-DC` ANDs `not ansible_facts['windows_domain_member']` onto every AccountPolicy task, after its
toggle, through the same fact and `when` merging as ADRs 0025 and 0026.

**On a DC, secedit sets every `[System Access]` value.** #175 set lockout duration and reset
through `Set-ADDefaultDomainPasswordPolicy`, on the premise that secedit would not take them on a
DC. That was the threshold-0 gap above, so the path is removed.

## Alternatives considered

**Skip account policy on every domain-joined host, a DC included**, as ansible-lockdown's
Windows-2022-STIG does. Rejected: on a DC the role can set the domain's policy, and Ansible may be
the only thing applying the STIG.

**Keep #175's path for duration and reset.** Rejected: two mechanisms for one section, kept for a
reason that turned out not to hold.

**The adapter emits the threshold beside duration and reset.** Rejected: it breaks one task per
rule and writes the threshold twice.

## Consequences

- A domain member's account policy is the domain's to get right; its role reports `skipping`.
- On a DC, writing `[System Access]` changes the Default Domain Policy. A rule's `_when` toggle is
  the opt-out for an organization that manages that policy by hand.
- `[Kerberos Policy]` behaves differently on a DC: a local write does not take. That is #234.

Decided in [#232](https://github.com/camusicjunkie/PowerStigConverter/issues/232).
