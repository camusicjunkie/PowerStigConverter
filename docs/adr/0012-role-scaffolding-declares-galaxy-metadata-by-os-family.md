---
status: accepted
---

# Role scaffolding declares galaxy_info and collection dependencies by OS family

No role this module generates, Windows or Linux, scaffolds `meta/main.yml`. A role still runs as
long as the operator already has the right collections installed, but it names neither them nor
the OS it targets to anyone consuming it through Ansible Galaxy or `ansible-galaxy role info`.
Surfaced while closing map #78 as a repo-wide gap, not a Linux one — filed as #94 for its own
design pass.

## Decision

**`meta/main.yml` is scaffolded once, like `vars/main.yml` and `handlers/main.yml`.** `Roles/`
gains `main_meta.yml` and `main_meta_linux.yml`, selected by Plaster's `condition` attribute on
`OsFamily` exactly like the task/default/handler pairs ADR 0007 already established. It is hand-
editable and untouched by `New-AnsibleRoleScaffold`'s already-exists guard; nothing in
`New-AnsiblePlaybook` regenerates it, so it is not tracked in the scaffold's returned paths.

**`collections:` is declared unconditionally per `OsFamily`, not per generator used.** Every
Windows task generator targets `ansible.windows` or `community.windows` (`win_dsc`, `win_acl`,
`win_regedit`, `win_service_info`, `win_user_right`, `win_feature`, `win_security_policy`,
`win_audit_policy_system`, `win_certificate_info`) — a Windows role always lists both. Every Linux
task generator (`nxFileLine`, `nxService`) targets `ansible.builtin` only, which ships with
ansible-core, so a Linux role's `meta/main.yml` carries no `collections` key at all. Tracking which
generators actually fired for one conversion would be more precise, but needs new machinery
threaded from dispatch through to the scaffold step for a distinction no real STIG currently
exercises — every in-scope Windows product's rule set already pulls from both collections.

**`galaxy_info.platforms` follows `OsFamily`/`OsMajorVersion`, the same facts
`Get-AnsibleOsAssertion` already produces for the runtime assert.** Windows: `[{name: Windows}]`.
Linux: `[{name: EL, versions: [<OsMajorVersion>]}]`. RHEL and OracleLinux both report
`ansible_os_family: RedHat` and both map to the Galaxy platform `EL` — the same one-family
treatment the runtime assert already gives them, keyed apart only by `OsMajorVersion`, exactly as
ADR 0007 does for the `ansible_distribution_major_version` check.

**`min_ansible_version` is pinned to `2.15`.** ADR 0009 already established 2.15–2.19 as this
module's tested ansible-core range (`lineinfile`'s regexp-as-bytes behavior, relevant to
`nxFileLine`). Pinning the floor of that range documents a fact this repo already verified rather
than inventing a new one.

**`galaxy_info.description` is built from `OsDescription`, the same value the Windows assert's
failure message already uses** (`'STIG hardening role for {0}'`) — no new Plaster parameter.

## Alternatives considered

**Per-generator collection tracking.** Rejected: no in-scope STIG needs the precision, and it
would require threading which generators fired through `ConvertTo-AnsiblePlaybook` and
`New-AnsibleRoleScaffold`, machinery this module has no other use for today.

**A single generic Linux platform (`GenericLinux`) instead of `EL`.** Rejected: it discards the
major-version precision `Get-AnsibleOsAssertion` already tracks and the runtime assert already
checks, for no simplification for the Plaster templates need to make.

**Leaving `min_ansible_version` unset.** Rejected: ADR 0009 already pins the floor of the range in
prose; leaving `meta/main.yml` silent about it would just make that fact harder to find, not
avoid asserting one that isn't already established.

## Consequences

- A fourth Linux product needing a Galaxy platform name other than `EL` is a new `switch` arm's
  worth of consideration, not a new file — same shape as `Get-AnsibleOsAssertion` already has for
  `OsFamily`/`OsMajorVersion`.
- A Windows generator that starts using a third collection needs this ADR revisited; nothing
  enforces the `collections:` list against what the generators actually emit.

Decided in [#94](https://github.com/camusicjunkie/PowerStigConverter/issues/94).
