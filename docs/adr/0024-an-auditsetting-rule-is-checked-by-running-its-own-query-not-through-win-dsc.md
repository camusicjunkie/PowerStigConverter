---
status: accepted
---

# An AuditSetting rule is checked by running its own query, not through win_dsc

`Build-AnsibleAuditSettingTask` emitted one `ansible.windows.win_dsc` task naming AuditSystemDsc's
`AuditSetting` resource. On Windows 11 every such task failed with `Not found` (#195). Calling the
resource directly showed why: the DSC engine loads `AuditSetting.psm1` under the machine execution
policy, and a Windows client's default is `Restricted`, so the module never loads (#208).
`win_powershell` bypasses the policy for its own process; `win_dsc` cannot.

Loading the module would not have been enough. AuditSystemDsc's `Set-TargetResource` is empty, so
on a non-compliant host the task reports `changed` and never fails. The rule's check was never
reaching the run's result, on Server either.

## Decision

**An AuditSetting rule emits a `win_powershell` gather and an `ansible.builtin.assert`, on every
Windows OS.** The gather runs `Get-CimInstance -Query` (with `-Namespace` when the rule names one)
and outputs the actual value of every instance that fails the rule's comparison; the assert fails
the task unless that output is empty, and lists what it found. The script is fixed text, the same
for every rule; the query, property, operator and desired value reach it as `parameters`. It
declares `SupportsShouldProcess` so it runs under `--check`, and never reports a change.

**The comparison keeps AuditSystemDsc's semantics.** The desired value is on the left and both
operands are strings, exactly as `Test-TargetResource` evaluates them, because PowerStig's data is
written for that order (#209). The operator goes through a fixed `switch` over `-eq`, `-ne`,
`-match`, `-notmatch`, `-like`, `-notlike`, `-lt`, `-le`, `-gt`, `-ge`, not `[scriptblock]::Create`;
any other operator throws, naming it, and fails the task.

**Task names read the comparison as it is evaluated**: `Assert 10.0.22621 -le Version`, not
`Version -le 10.0.22621`.

## Alternatives considered

**Document `RemoteSigned` as a prerequisite of a client role.** Rejected: with an empty `Set`, the
role would then load the resource and still report nothing useful.

**Set the execution policy in a pre-task.** Rejected: it is a machine-wide security change the STIG
does not ask for, and a decision for the organization rather than a role.

**`community.windows.win_disk_facts` and other fact modules.** Rejected: each covers one query
shape, so the generator would need its own WQL-to-Jinja translation for every one (ADR 0005's grain).
The generic script reproduces PowerStig's semantics for any query.

**Numeric or version-aware comparison.** Rejected: it would change what PowerStig's data means.
String semantics are kept for fidelity, quirks included.

## Consequences

- A role no longer needs AuditSystemDsc on the target, and a Windows client role has no `win_dsc`
  task at all.
- IIS and SQL Server roles still use `win_dsc`, so their targets need an execution policy that
  loads resource modules; `README.md` says so.
- A rule whose operator PowerStig spells some other way fails at run time rather than being
  silently passed. Correct such data in `RuleCorrection.psd1` (ADR 0020).

Decided in [#216](https://github.com/camusicjunkie/PowerStigConverter/issues/216).
