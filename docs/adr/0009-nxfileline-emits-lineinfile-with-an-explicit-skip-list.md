---
status: accepted
---

# nxFileLine emits lineinfile, with an explicit skip list for what it cannot

`Build-AnsibleNxFileLineTask` covers 420 of this map's 422 in-scope rules — by far the largest
generator this repo has built. The base shape was settled going in: one `ansible.builtin.lineinfile`
per rule, `ContainsLine`→`line`, `DoesNotContainPattern`→`regexp`, `FilePath`→`path`, `create` left
at its default `false`, `become: true` in the task's own `Body` (the ADR 0006/0007 pattern,
matching `Build-AnsibleNxServiceTask`). What this ADR settles is everything PowerStig's data does
not fit that shape cleanly.

## Decision

### Skip-and-warn, one guard, four conditions

A rule is skipped (the generator returns `$null` for it, `ConvertTo-AnsibleTask` already discards
a `$null` build) when any of:

- `FilePath` ends in `/` — a directory, not a file (#81, 26 rules).
- `DoesNotContainPattern` fails to compile under .NET or Python `re` (#89, 3 rules).
- `ContainsLine` carries a non-ASCII character (#90, 1 rule — a non-breaking space).
- `Id` is in an explicit, hand-maintained list of the 35 rules whose `ContainsLine` is check-text
  prose rather than a line (#88's population, this ADR).

No separate "unparsed rule" guard exists. Checked against the current data: 7 of the 8 in-scope
`dscresource="None"` rows carry a `DuplicateOf` and are already discarded by
`ConvertTo-AnsibleTask`'s existing duplicate skip before any adapter runs; the 8th
(`V-271725`, OracleLinux-9-1.1) has `FilePath` of `/etc/sudoers.d/`, already caught by the
directory guard above. The three rules that looked like they needed `ini_file` or a site-supplied
repo name (`V-248527`, `V-248870`, `V-248574`) all have a `FilePath` ending in `/` too, for the
same reason — `dconf`/`yum.repos.d` drop-in directories, not files. Both populations turned out to
be subsets of the directory guard, not cases of their own.

### The 35 prose-`ContainsLine` rules: skipped, not recovered, keyed by an explicit list

#88 found 9 of the 35 have their real line quoted in `RawString`; the other 26 do not exist
anywhere on the rule (16 of those are file-permission/ownership checks that were never
legitimately `nxFileLine`). Recovering the 9 means regex-matching free-text check prose
("Verify... with the following command... If X, this is a finding.") to pull out the one clause
that's a real config line — the converter parsing STIG prose by hand, which is PowerStig's job
(see the map's Out of scope section on unparsed rules) and which ADR 0005 already rules out in
spirit: a generator reads the rule's structured fields, not its narrative text.

All 35 are skipped uniformly. The guard is keyed on an explicit list of the 35 rule ids, not a
runtime predicate. #88's own research is explicit that its keyword scan
(`\bfinding\b|\bcheck\b|\bverify\b|...`) was "tuned for manual review... not proven to have zero
false positives against future STIG revisions" — reusing it as a generator-time guard risks
silently skipping a rule whose legitimate `ContainsLine` happens to contain "finding" (the
predicate's own false positive, V-257779's DoD banner, is exactly this failure mode). A closed,
enumerable list for the three currently in-scope revisions cannot misfire that way, and matches
how this module already treats upstream drift elsewhere — OracleLinux-8's unparsed count moved
from 54 to 0 between revisions by re-verifying against the new data, not by re-deriving a
predicate.

### Organization-value rules: 24 across the three products, one `OrganizationData.psd1` entry

Not 6 — the map's Notes recorded 6 for RHEL-9-2.8 alone (125 + 6 = 131). Across RHEL-9-2.8 (6),
OracleLinux-8-2.4 (15) and OracleLinux-9-1.1 (3) there are 24. Every one of those rules'
`OrganizationalSetting` node carries both a `ContainsLine=""` and a `DoesNotContainPattern=""`
attribute — PowerStig leaves both blank and expects the organization to supply the whole line and
its commented-out form. `FilePath` is always present, even on these rows; it is never itself an
organization value.

```powershell
'nxFileLine' = @{
    'Required' = @('ContainsLine', 'DoesNotContainPattern')
    'Shape' = @{
        'line' = 'ContainsLine'
        'regexp' = 'DoesNotContainPattern'
    }
}
```

This is the same multi-`Required`-field-plus-`Shape` pattern `IisLogging` already uses — no new
capability needed in `Resolve-AnsibleOrganizationValue` or the completeness check.

### `GroupDetail`: the distinct `FilePath` leaves, in order of appearance

Sub-rule groups sharing one `FilePath` are common and fit `Build-AnsibleRegistryTask`'s pattern
directly (`GroupDetail` = the leaf). But a meaningful fraction of groups edit **more than one**
file for a single requirement — 5 of RHEL-9's 18 groups, 13 of OL-8's 28, 3 of OL-9's 15 (e.g.
`V-248828`: `/bin/false` and `/etc/modprobe.d/`). `Registry`'s "one shared key" premise doesn't
hold, and no field on the rule carries a human-authored requirement name — `Title` is the SRG
control id, not prose.

`GroupDetail` is the distinct `FilePath` leaves the group's rules touch, joined in the order the
sub-rules appear. Mechanical, derived only from data the rule already carries — no invented label.

### `Detail`: `ContainsLine` inlined verbatim, no truncation

`'Ensure {0} contains "{1}"' -f <FilePath leaf>, $Rule.ContainsLine`. Matches every other
generator's `Detail` convention of inlining the value it sets rather than summarising it (e.g.
`Build-AnsibleRegistryTask`'s `'Set {0}' -f $Rule.ValueName`). `ContainsLine` up to a full config
line's length is normal; truncating would be the generator deciding how much of the STIG's own
text is worth showing. (The one rule whose `ContainsLine` is genuinely unbounded — V-257779's
13-line banner — does not reach this path at all; see below.)

### Multi-line `ContainsLine`: `ansible.builtin.copy`, not `lineinfile` (#91)

`ContainsLine -match "` + '`' + `n"` branches to `ansible.builtin.copy` with `content:`, ignoring
`DoesNotContainPattern` (`copy` has no regexp concept; it's idempotent by content). `Detail` gets
generic wording, not the inlined banner. One rule today (`V-257779`), treated as a shape rather
than an id special case since a future Linux product could plausibly add another banner-to-file
rule.

### Anchoring and regex-key derivation: neither — already settled, out of scope here

#80 already decided `DoesNotContainPattern` ports to `regexp` verbatim, no translation, no
escaping, no normalisation — that decision covers both fog items the map flagged as feeding this
ticket. #80's own research found the generated tasks are already idempotent for the case that
matters (`lineinfile`'s byte-exact fallback catches an already-compliant line even though the
unanchored pattern doesn't match it — self-match 0 of 396). The one edge that remains — a
compliant line spaced differently from the STIG's exact wording gets a second line appended,
reachable through 275 of 396 non-org-value rules' `#`-prefixed patterns — is accepted as a known,
documented limitation. Anchoring the pattern or deriving a new one from the setting key would both
mean the converter authoring a regex PowerStig never wrote, the class of decision ADR 0005 already
rules against.

## Alternatives considered

**Recover the 9 `RawString`-recoverable prose rules.** Rejected — see above. Splitting the 35 into
"recoverable" and "not" would also mean two different skip predicates instead of one, for a
9-rule gain that still leaves 26 uncovered.

**A runtime keyword predicate for the prose guard**, reusing #88's scan. Rejected: proven to have
at least one false positive today and explicitly not validated against future data by the research
that produced it.

## Consequences

- `Build-AnsibleNxFileLineTask` needs no logic keyed on `dscresource` — every "unparsed" and
  "wrong module" case in the current data resolves through the duplicate skip or the directory
  guard already required for other reasons.
- The 35-id skip list (and the population behind the other three skip conditions) is data this
  module owns and must revisit each time the map's Notes says to re-pull upstream — the same
  posture already adopted for the unparsed-rule population.
- `OrganizationData.psd1` gains one entry, following an existing pattern exactly; no change to
  `Resolve-AnsibleOrganizationValue` itself.
- 26 of the 35 skipped prose rules (16 of them file-permission checks) remain permanently
  uncovered by this generator regardless of any future upstream fix to `ContainsLine`, since
  `nxFileLine` was never the right DSC resource for them — a fact for `Not yet specified` to carry
  forward, not something this generator can resolve.

Decided in [#83](https://github.com/camusicjunkie/PowerStigConverter/issues/83).
