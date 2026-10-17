---
status: accepted
---

# A role is not named for a STIG's `All` scope

`New-AnsiblePlaybook` named a role by lower-casing the STIG name, so `WindowsDefender-All` became
`windowsdefender_all`. ADR 0013 had already decided that `All` is a STIG's scope, not a release:
it covers every release of its product, so it has no sibling to be told apart from. It stripped
`All` from the variable prefix (`stig_defender`), but the role name never went through that
code, leaving `windowsdefender_all` beside variables named `stig_defender_*`.

## Decision

**A role's default name is the STIG name without a trailing `-All`.** The strip is `-All$`,
anchored and requiring the dash, exactly as in ADR 0013, and lives in `Get-AnsibleRoleName`.

| STIG name | Role |
| --- | --- |
| `WindowsDefender-All` | `windowsdefender` |
| `WindowsFirewall-All` | `windowsfirewall` |
| `FireFox-All` | `firefox` |

Everything else is unchanged: `WindowsServer-2025-MS` is still `windowsserver_2025_ms`. `-RoleName`
still overrides the default.

## Alternatives considered

**Reuse the variable prefix rules for the role name** (`defender`, `firewall`, `server_2025`).
Rejected: dropping `Windows` shortens every Windows role and stops it resembling the STIG it came
from. ADR 0013 drops the word from a prefix because it distinguishes nothing among variables; a
role name is read next to other products' roles, where it still does.

**Leave `_all`.** Rejected: it reads as though a `windowsdefender_2022` sibling existed, the same
objection ADR 0013 raised against `stig_defender_all`.

## Consequences

- A role already generated as `windowsdefender_all` is not renamed. Generation never overwrites an
  existing role, so regenerating produces a second directory beside it; delete the old one.
- Tracing a role back to `WindowsDefender-All-2.8.xml` goes through the role's `meta/main.yml`
  description, the same as the variable prefix.
