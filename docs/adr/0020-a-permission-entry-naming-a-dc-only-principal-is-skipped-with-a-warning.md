---
status: accepted
---

# A Permission entry naming a DC-only principal is skipped with a warning

`WindowsServer-2025-MS-1.1` V-278001.c grants `Server Operators` read on `HKLM:\SYSTEM`. That
group exists only on a domain controller, so on a member server the task fails with
`account_name Server Operators is not a valid account`. A survey of every member-server and client
STIG in PowerStig found this the only such entry in a Permission rule.

On a product that is not a domain controller (its name does not end in `-DC`), the generator leaves
out an entry whose principal is listed in `Source/Files/DomainControllerOnlyPrincipal.psd1` and
writes a warning naming the rule, the principal and the product. A rule left with no entry builds
nothing, as with the `(RX)` entries of #174. Extending the list is a one-line data edit.

## Considered options

- **Leave it to the organization** — rejected: it adds a variable, a `defaults/` line and an assert
  to every Permission rule to cover an entry that can never apply to the host.
- **Warn at conversion but still emit the task** — rejected: the role then fails on every run for
  a reason the converter already knew.

## Consequences

- The skip follows the STIG's own scope: a product ending in `-DC` keeps the entry. A site that
  runs a member-server role on a domain controller loses that one entry.
- The list is small and hand-kept. A DC-only principal not on it fails in the lab until added.
