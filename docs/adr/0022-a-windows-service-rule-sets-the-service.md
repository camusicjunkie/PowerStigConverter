---
status: accepted
---

# A Windows Service rule sets the service

`Build-AnsibleServiceTask` used to gather a service with `win_service_info` and assert its running
state. Nothing recorded why; it had done so since the generators were first written. It never
checked the startup type its task was named for, and on a fresh Windows 11 install it failed
V-253289 (Secondary Logon disabled and stopped) on every run, because nothing in the role ever
disabled the service. The Linux side already sets a service: nxService emits `systemd_service`
with `enabled` and `state` (ADR 0008).

## Decision

**A Service rule emits `ansible.windows.win_service` with the rule's startup type and state.**
`start_mode` maps PowerStig's DSC words (`Automatic`, `Manual`, `Disabled`) to `win_service`'s
(`auto`, `manual`, `disabled`); `state` maps `ServiceState` (`Running` → `started`, `Stopped` →
`stopped`) as #100 decided. An unrecognised word throws at conversion rather than guessing.

**An organization value still reaches the task as a variable (ADR 0003).** The service name is
referenced directly. The startup type variable holds PowerStig's word, as the org settings file
gives it, so the mapping runs in Jinja when the play runs; a word `win_service` already knows
passes through, so `-e` can give either.

**A service the target does not have is decided by which way the rule points.** The task gathers
the service first. A rule that wants it running asserts it is installed, so the missing service is
a failure that says so. A rule that wants it stopped skips the set: a service that is not there is
already not running, and `win_service` would fail on the unknown name. (#170 found the old assert
failing on the list shape; this replaces it.)

Unlike a certificate rule, nothing about a service needs data the role does not have, so there is
no reason to stop at checking.

## Alternatives considered

**Keep asserting, and fix the assert to check the startup type too.** Rejected: the role is meant
to remediate. A check-only rule leaves every non-compliant host non-compliant and reports the same
failure every run, which is what V-253289 did.

**Let `win_service` fail on a missing service whichever way the rule points.** Rejected: it fails a
rule whose requirement the host already meets — a Server Core image without Secondary Logon has
nothing to disable.

**Map the startup type at conversion and declare `auto` in `defaults/`.** Rejected: the org
settings file speaks PowerStig's vocabulary, and the declared default would no longer match the
value the operator wrote there.

## Consequences

- A Service rule changes the target. Check mode reports what it would change, as every other
  setting generator does.
- `win_service_info` stays in the task, only to decide the missing-service case.

Decided in [#197](https://github.com/camusicjunkie/PowerStigConverter/issues/197).
