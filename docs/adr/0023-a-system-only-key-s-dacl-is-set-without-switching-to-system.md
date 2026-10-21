---
status: accepted
---

# A SYSTEM-only key's DACL is set without switching to SYSTEM

`HKLM:\SECURITY` and `HKLM:\SAM\SAM` can be read only by SYSTEM, so `Build-AnsiblePermissionTask`
ran the `win_acl` for a rule on either under `become_user: SYSTEM` with `become_method: runas`
(#147). Runas reaches SYSTEM through `CreateProcessWithTokenW`, which needs the Secondary Logon
service. Since ADR 0022, a Windows 10 or 11 role disables that service (V-253289, V-220732)
earlier in `cat2.yml` than V-253431 sets SECURITY's DACL, so V-253431 failed with Win32 error 1058,
"the service cannot be started … because it is disabled". Before ADR 0022 the Secondary Logon rule
never took effect, which is why this never showed.

On the Windows 11 lab host the default DACLs are:

| Key | DACL | Administrators |
|---|---|---|
| `SECURITY` | `O:BAG:SYD:P(A;CI;KA;;;SY)(A;CI;RCWD;;;BA)` | `ReadPermissions, ChangePermissions` |
| `SAM\SAM` | `O:BAG:SYD:P(A;CI;KA;;;SY)(A;CI;RCWD;;;BA)` | `ReadPermissions, ChangePermissions` |
| `SAM` | `O:BAG:SYD:PAI(A;CI;KA;;;CO)(A;CI;KA;;;SY)(A;CI;KA;;;BA)…` | `FullControl` |

Administrators may rewrite the DACL of every one of them without reading the key. `win_acl` run
without `become` still fails, "Requested registry access is not allowed", because it opens the key
for more than that.

## Decision

**A Permission rule on a path under `HKLM:\SECURITY` or `HKLM:\SAM` emits
`ansible.windows.win_powershell` instead of `win_acl`, and no `become`.** The script opens the key
with `ReadPermissions, ChangePermissions` alone, adds the entry with `AddAccessRule`, and writes the
DACL back only when that changed it. It is fixed text; the entry reaches it as `parameters` —
the key, principal, rights, type, inheritance and propagation `win_acl` would have been given — so
every such task carries the same script.

**It reports like a module.** `changed` comes from comparing the DACL before and after the rule is
added, and the script declares `SupportsShouldProcess`, which is what makes `win_powershell` run it
under `--check`, where it reports the change without writing. On the lab host: an entry already
present is `ok`; a new one is `changed` in check mode with the DACL untouched, and `changed` with it
written otherwise.

**Every other Permission rule still emits `win_acl`.**

## Alternatives considered

**Start Secondary Logon around the task and disable it again**, keeping `win_acl` under runas.
Rejected: the host is out of compliance with V-253289 for the length of the task on every run, and
the role has to restore the service even when the task between fails. It stays ordinary Ansible, so
it was the fallback had the DACL not been writable by Administrators.

**Order V-253431 ahead of the Secondary Logon rule.** Rejected: it depends on the order severity
files and rule ids happen to give, and breaks silently when either changes.

**A scheduled task, or `community.windows.win_psexec`, running as SYSTEM.** Rejected: the outcome is
whatever the scheduled process reports back, `--check` cannot preview it, an interrupted run leaves
the task behind, and it needs SYSTEM for a change Administrators may already make.

## Consequences

- Writing the DACL through .NET sets its auto-inherited flag (`P` becomes `PAI`); the access it
  grants is unchanged. A scan comparing raw SDDL would see the difference.
- `win_acl`'s other behaviour — `state: absent`, its own principal resolution — is not reproduced.
  No STIG rule asks for either on these keys; principals resolve through .NET's `NTAccount`.
- If a later Windows release stops granting Administrators `WRITE_DAC` on SECURITY, these tasks
  fail on opening the key, and the fallback above is the one to revisit.

Decided in [#200](https://github.com/camusicjunkie/PowerStigConverter/issues/200).
