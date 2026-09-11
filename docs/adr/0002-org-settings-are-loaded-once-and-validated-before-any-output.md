---
status: accepted
---

# Org settings are loaded once and validated before any output

Reading the org settings file was spread across `Get-AnsibleOrganizationValue` and
`Export-AnsibleOrganizationValue`, each doing `[xml] Get-Content` *inside* its per-rule loop — the
same file parsed once per rule from two places, with a standing `TODO` to consolidate them. That
left no single point at which the inputs could be judged complete, which ADR-0001 requires.

One function now loads the org settings file once into an id-to-values map. `New-AnsiblePlaybook`
validates that map against the rules *before* `New-AnsibleRoleScaffold` touches the disk, and the
same map then feeds the task generators and the exporter. Nothing partial is ever written, the
check is testable without generating a role, and the duplicated read disappears.

## Consequences

- Completeness is judged per rule type against a declared list of the fields that type's task
  actually consumes, held in `OrganizationData.psd1` alongside the existing name/value keys.
  Previously one designated field stood in for all of them, so a `Service` rule with a blank
  `StartupType` passed the check and produced a half-empty task.
- The failure is a single terminating error whose message lists every gap for a human and whose
  `ErrorRecord.TargetObject` carries them as objects — rule id, rule type, field, and whether the
  setting was missing or unanswered. Tests assert on the objects, not on prose.
