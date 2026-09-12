---
status: accepted
---

# Every organization value is a role variable

Organization values reached the generated role three different ways. Four rule types emitted a
`{{ prefix_id_name }}` reference resolved from `defaults/`; `RootCertificate` and `Service`
inlined literals and were excluded from the exporter by name; `IisLogging` referenced a variable
for its log path but inlined the five values that come from the org settings file. Two task
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

## Two values that cannot be a plain scalar variable

- **`RootCertificate`'s store.** The org settings file holds a store *path*
  (`Cert:\LocalMachine\Root`) but `win_certificate_info` takes a store *name* (`Root`) and a store
  *location* (`LocalMachine`) as separate parameters, so that value was always going to be taken
  apart before it reached Ansible. It is taken apart at generation time and the variables hold the
  values the module consumes, which are the values the assert's non-empty checks should be about.
  `defaults/` therefore does not echo the org settings file verbatim for this one type.

  > **Amended, see [#4](https://github.com/camusicjunkie/PowerStigConverter/issues/4).** This
  > originally said the variable holds the store name, singular: only the leaf was taken and the
  > `LocalMachine` segment was dropped, leaving `win_certificate_info`'s own default to stand in.
  > That was right by luck for every store under `Cert:\LocalMachine\` and silently wrong for
  > anything under `Cert:\CurrentUser\`, where the role checked a store the STIG never named. One
  > answered question now becomes two organization variables, named `store_name` and
  > `store_location` for the parameters they feed; `OrganizationData.psd1` declares the split.
- **`IisLogging`'s `LogCustomFields`.** It is a nested structure built from the org node's entries,
  not a scalar, so it stays generated in place. It is the one field `OrganizationData.psd1` marks
  optional, so nothing asserts on it and it needs no variable to be filled in.

`IisLogging`'s `LogPath` is the other way round and was already correct: no org settings attribute
feeds it, so it is a blank organization variable by design, declared in `defaults/` and referenced
by the task, for the site to fill in.

> **Amended by [ADR-0004](0004-one-function-answers-every-organization-value-question.md).** Calling
> `LogPath` an *organization variable* contradicts `CONTEXT.md`, which defines one as holding an
> organization value — and no org settings attribute feeds `LogPath`, as this paragraph itself says.
> ADR-0004 resolves the contradiction the other way: it is a role variable the site fills in, not an
> organization variable, and it is declared outside the organization value machinery. Everything
> else in this paragraph — blank by design, declared in `defaults/`, referenced by the task — stands.
