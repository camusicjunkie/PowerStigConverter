---
status: accepted
---

# A Linux task escalates but carries no identity

Every generator this repo had before Linux emitted `ansible.windows.win_dsc`, and the SQL map
settled a single rule for all of them: no generator emits a credential or `become`. The reasoning
was that the connection identity is the adopting site's business — credentials do not belong in
`defaults/`, `win_dsc` PSCredential parameters leak without `no_log`, and emitting one would be
the converter inventing a fact about the target environment.

Linux breaks half of that. `nxFileLine` writes `/etc/issue`, `/etc/login.defs`,
`/etc/audit/auditd.conf`; `nxService` enables and disables systemd units. An unprivileged
`lineinfile` on `/etc/login.defs` fails, and unlike the SQL case there is no site-side equivalent
of "make the connection user a sysadmin" that avoids escalation altogether.

## Decision

Linux generators emit `become: true` on every task. They still never emit a credential,
a `become_user`, or a `become_method`.

The two halves of the SQL decision come apart, and the line between them is whether the rule
itself says so:

- **Escalation is implied by the rule.** A rule whose `FilePath` is `/etc/audit/auditd.conf` is
  stating that it writes to root-owned configuration. That is a fact carried in the rule data, so
  the converter is reading it, not inventing it.
- **Identity is not.** *Which* account connects, and how it escalates, is a fact about the target
  environment that no STIG rule carries. `become_user` defaults to root, `become_method` to the
  site's configured default, and both stay unstated.

## Alternatives considered

**Leave `become` to the site's playbook.** A site can set `become: true` at the play level, and
some house styles require exactly that. Rejected because the generated role is meant to be
correct when imported as-is: a role that silently no-ops or fails on every task unless the
importer knows to add one line is not a converted STIG, it is a draft of one. The Windows roles
run correctly as imported, and the Linux ones should meet the same bar.

**Emit `become` only on the tasks that need it.** Rejected because it requires deciding which
paths are root-owned, which is a fact about the target filesystem rather than about the rule —
the error [ADR 0005](0005-a-rule-s-path-is-emitted-as-the-stig-wrote-it.md) already names. Every
rule in scope writes privileged configuration in any case, so the distinction would buy nothing
and would have to be maintained by hand.

## Consequences

An operator who wants a different escalation path overrides it in inventory or play vars, the
same way they would override any other role default. A site that forbids `become` outright cannot
use the generated Linux roles unedited; that is the intended trade, since such a site cannot apply
the STIG either.

`become` is a play-level keyword, not a module argument, so it sits beside `name` and `when` on
the task rather than inside the module hash. Where it gets attached is left open: the task-level
keys are owned by `ConvertTo-AnsibleTask`, which is deliberately rule-type agnostic and must not
start branching on rule type — so attaching it there would put `become` on Windows tasks too.
Whether the adapters declare it, or the role template carries it once at the play level, is
settled by the ticket that designs the first Linux generator.
