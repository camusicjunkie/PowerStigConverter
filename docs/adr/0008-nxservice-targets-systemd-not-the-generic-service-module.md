---
status: accepted
---

# nxService targets systemd_service, not the generic service module

`Build-AnsibleNxServiceTask` is the first generator in this repo that does not emit
`ansible.windows.win_dsc` — the first one built against a native Ansible module instead. Ansible
offers two candidates for a service requirement: `ansible.builtin.service`, a generic wrapper that
autodetects the init system, and `ansible.builtin.systemd_service`, which manages systemd units
directly. Every in-scope product — RHEL-9, OracleLinux-8, OracleLinux-9 — is systemd-era.

## Decision

`Build-AnsibleNxServiceTask` emits `ansible.builtin.systemd_service`. `name` comes from `Rule.Name`;
`enabled` from `Rule.Enabled -eq 'True'`, an explicit boolean per #69; `state` is emitted only when
`Rule.State` is non-empty, matching how the field already arrives from PowerStig.

The generic module's whole value is autodetecting an init system the generator would otherwise
have to guess at. This generator never has to guess: it already knows, the same way a Windows
generator already knows it's targeting Windows. Routing through the generic wrapper anyway would
trade a module with precise, systemd-specific semantics for `enabled` (it manages the unit symlink
directly) for one whose main feature is solving a problem this scope doesn't have.

## Alternatives considered

**`ansible.builtin.service`**, for portability if a non-systemd Linux product ever enters scope.
Rejected: that portability is speculative today — no in-scope product needs it — and buying it now
means every current rule gets vaguer `enabled` semantics for a future that may not arrive. A
non-systemd product, if one is ever added, is its own fork point (a second adapter, or an explicit
branch here); it is not a reason to blur this generator now.

## Consequences

- A future non-systemd Linux product means revisiting this generator specifically, not just the
  role scaffolding — it is not automatically portable the way a generic-module choice would have
  been.
- Sets the pattern for later Linux generators: prefer the Ansible module the in-scope products
  actually need, not the most generic one available.

Decided in [#82](https://github.com/camusicjunkie/PowerStigConverter/issues/82).
