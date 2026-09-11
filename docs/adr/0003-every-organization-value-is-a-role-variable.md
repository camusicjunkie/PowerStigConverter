---
status: accepted
---

# Every organization value is a role variable

Organization values reached the generated role three different ways. Four rule types emitted a
`{{ prefix_id_name }}` reference resolved from `defaults/`; `RootCertificate` and `Service`
inlined literals and were excluded from the exporter by name; `IisLogging` was excluded by a
special case that emitted an always-blank `logpath` variable nothing referenced. Two task
generators mutated `OrganizationValueRequired` on the rule they were handed purely to steer the
exporter's filter, which made them non-idempotent over the same rule object.

All seven rule types now use the same indirection: one flat organization variable per field
(`prefix_id_servicename`, `prefix_id_startuptype`, `prefix_id_logflags`), declared in `defaults/`
and referenced from the task. Flat rather than a nested mapping so that a single field can be
overridden with `-e` and so an assert can name the exact field that is missing.

With `-AllowIncompleteOrganizationValue` (ADR-0001), an unanswered setting produces the variable
declared blank plus an `ansible.builtin.assert` guarding the block, so the operator finishes the
role by editing `defaults/` rather than regenerating, and "conversion succeeded" can never mean
"silently sets the wrong value". Asserts are generated only for settings that were unanswered at
generation time — they double as a list of the questions nobody answered, and they disappear on
regeneration once the org settings file is filled in.

## Consequences

- The exporter's `OrganizationValueRequired` filter goes away, and with it the only reason the two
  write-backs existed. Both are deleted; the task generators become idempotent over the same rule.
- Generated role output changes shape for `RootCertificate`, `Service` and `IisLogging`. The module
  is pre-1.0 and unpublished, so this is a `0.2.0` bump and a README table update rather than a
  migration.
