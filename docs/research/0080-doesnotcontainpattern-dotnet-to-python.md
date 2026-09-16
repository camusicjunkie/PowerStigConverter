# Do PowerStig's `DoesNotContainPattern` regexes port from .NET to Python `re`?

Research for [#80](https://github.com/camusicjunkie/PowerStigConverter/issues/80), a child of the
RHEL 9 / Oracle Linux coverage map [#78](https://github.com/camusicjunkie/PowerStigConverter/issues/78).

Sources: the processed STIG XML in the local upstream PowerStig clone
(`$env:LOCALAPPDATA\PowerStig\source`, branch `dev`) for `RHEL-9-2.8`, `OracleLinux-8-2.4` and
`OracleLinux-9-1.1`; the `ansible/ansible` source for `lib/ansible/modules/lineinfile.py`;
.NET 10.0.10 `System.Text.RegularExpressions` and CPython 3.14.4 `re` run against each other.

## Verdict

**Yes, with three exceptions and one divergence — none of them the one the ticket expected.**

Of the 282 distinct patterns the three products carry:

- **279 compile in both engines and agree on every one of 1,139,844 pattern/line comparisons** —
  same match/no-match *and* the same matched span, in both of `lineinfile`'s regex modes. The
  constructs the ticket listed (`\s*`, `\w*`, `\b`, anchors, alternation, negative lookahead) all
  port unchanged. So do `(?:…)`, `{2,}` and a character class, which the ticket did not list.
- **3 do not compile in *either* engine.** They are malformed regex, so this is a PowerStig
  authoring defect, not a porting one — .NET DSC never ran them either.
- **1 of the 279 diverges** between .NET and `lineinfile` as currently shipped, on a
  non-breaking space, because `lineinfile` compiles the pattern as **bytes**.

The larger risks found are not about the port at all: they are about **anchoring** and about what
`lineinfile` does when the pattern matches *nothing*. Those are in Findings 4–8.

## Method

1. Every `//nxFileLineRule/Rule` was read from the three products' processed XML: **428 rules**,
   of which 8 are unparsed (`dscresource="None"`) leaving **420 in scope**. 396 carry a
   `DoesNotContainPattern`; the 24 that do not are exactly the 24 with
   `OrganizationValueRequired="True"` (6 on RHEL-9, matching the map's note). Distinct patterns:
   **282**.
2. A corpus of **4,042 lines** was built: every `ContainsLine` in the three products plus 15
   mutations of each (commented, re-indented, tab-separated, case-folded, trailing whitespace,
   CR-terminated, `=` re-spaced), plus ~70 adversarial lines aimed at the specific characters
   where .NET and Python classify `\w`/`\s`/`\d`/`\b` differently — U+001C–U+001F, U+0085,
   U+00A0, U+2028, U+200B, U+0301, U+00B2, U+0660, U+2160, U+00AA.
3. Each pattern was matched against each line in three engines, recording
   *(matched?, start, length)* per pair:
   - **.NET** — `System.Text.RegularExpressions.Regex`, default options.
   - **py-bytes** — pattern and subject encoded UTF-8, `re.search`. This is `lineinfile` as
     shipped in every released ansible-core.
   - **py-str** — `str` pattern, `str` subject, `re.search`. This is `lineinfile` on `devel`.

   Subjects carried a trailing `\n`, because `lineinfile` searches lines straight out of
   `readlines()` with the terminator still attached.
4. The three result vectors were diffed pairwise.

Scripts and raw result vectors were throwaway; everything above is reproducible from the two XML
inputs and the recipe here.

## How `lineinfile` actually applies the pattern

Read from `lib/ansible/modules/lineinfile.py`, `present()`. This matters for every finding below,
and two of its properties are not what you would assume.

- **The pattern is compiled as bytes, and so is the subject.** On `stable-2.15` through
  `stable-2.19` (lines 309–343 of the 2.19 file):

  ```python
  with open(b_dest, 'rb') as f:
      b_lines = f.readlines()
  ...
  bre_m = re.compile(to_bytes(regexp, errors='surrogate_or_strict'))
  ...
  match_found = bre_m.search(b_cur_line)
  ```

  In a bytes pattern Python's `\w`, `\s`, `\d` and `\b` are **ASCII-only**. .NET's are
  Unicode-aware. That is the entire divergence surface, and Finding 3 is the one place the corpus
  reaches it.

  `devel` (so, presumably 2.20) has changed to text mode — `open(b_dest, 'r', encoding=encoding)`
  and `re.compile(regexp)` on `str` — which makes the classes Unicode-aware and **removes** the
  divergence. A generator that is correct today stays correct; one that relied on the ASCII-only
  behaviour would not.

- **No flags.** `re.compile()` is called with no flags, so no `re.MULTILINE`, no `re.IGNORECASE`.
  With one line per subject that matches .NET's defaults.

- **`re.search`, not `re.match`.** Unanchored. See Finding 4.

- **The last match wins**, not the first, unless `firstmatch: true` is set.

- **When the regexp matches nothing, there is a second pass** (lines 362–366) that looks for a
  line byte-equal to `line` after stripping `\r\n`. If it finds one, nothing changes; otherwise
  the line is appended at EOF. This fallback is what keeps the generated tasks idempotent — see
  Finding 5 — and its byte-exactness is what makes Finding 6 bite.

## Finding 1 — 279 of 282 patterns port with zero observed divergence

1,139,844 comparisons per engine pair. `.NET` vs `py-str`: **0 boolean divergences, 0 span
divergences**. `.NET` vs `py-bytes`: 0 span divergences and 3 boolean divergences, all from the
single pattern in Finding 3.

Span agreement is the stronger result and worth stating explicitly: both engines are
leftmost-first backtracking NFAs with the same alternation preference, so they do not merely agree
on *whether* a line matches but on *which* substring matched. Alternation order — the risk in a
pattern like `^#\s*ocredit.*$|^ocredit\s*=\s*(?!-1)\w*$` — behaves identically.

Construct census over the 282 distinct patterns:

| construct | patterns |
|---|---|
| `\s` | 282 |
| `*` | 282 |
| `.` | 48 |
| `$` | 15 |
| capture group `(` | 10 |
| alternation `\|` | 7 |
| `^` | 6 |
| negative lookahead `(?!` | 6 |
| `\w` | 5 |
| `+` | 3 |
| `\b` | 2 |
| `(?:`, `\d`, `[…]`, `{n,}` | 1 each |

Absent entirely, and therefore not a risk: lookbehind (Python forbids variable-length, .NET allows
it), named groups (`(?<n>)` vs `(?P<n>)`), inline flags, atomic groups, conditionals,
backreferences, `\A`/`\Z`/`\z` (where .NET's `\Z` and Python's `\Z` genuinely differ),
possessive quantifiers, `\p{…}` Unicode categories, and `\Q…\E`. Every one of the constructs that
would have broken the port simply is not used.

## Finding 2 — 3 patterns are malformed and compile in neither engine

All three are `OracleLinux-8-2.4`, all `dscresource="nxFileLine"`, all parsed and therefore
in-scope for the generator:

| rule | file | pattern | error |
|---|---|---|---|
| `V-248631.a` | `/etc/security/limits.d/` | `#\s**\s*hard\s*core\s*0` | nested quantifier at offset 4 |
| `V-248631.b` | `/etc/security/limits.d/` | `#\s*This\s*can\s*be\s*set\s*as\s*a\s*global\s*domain\s*(with\s*the\s**\s*wildcard)\s*…` | nested quantifier at offset 69 |
| `V-248723.d` | `/var/log/messages` | `#\s**.*\s*/var/log/messages` | nested quantifier at offset 4 |

.NET: `Invalid pattern … Nested quantifier '*'.` Python: `multiple repeat at position 4`.

The cause is the same in all three: PowerStig templated the STIG's literal `*` (the `limits.conf`
domain wildcard, the `rsyslog` facility wildcard) into the pattern **unescaped**, directly after
`\s*`, producing `\s**`. The correct pattern would be `\s*\*`.

This is not a porting problem — it is broken in the engine it was authored for — but it is a
porting *consequence*: on Windows nothing ran these, whereas `lineinfile` will raise `re.error` and
**fail the task at run time on the target host**. Three rules in a 420-rule role failing the play
is a worse outcome than three rules silently doing nothing.

The build ticket needs a decision. The options are to let it fail (honest, noisy), to skip a rule
whose pattern does not compile, or to correct `\s**` to `\s*\*` on the way out. Correcting it is
the converter asserting a fact the STIG did not state, so it is not obviously right — but neither
is shipping a role that cannot run. Flagged to the map as a new ticket.

## Finding 3 — the one real .NET/Python divergence: `\s` and U+00A0

`OracleLinux-9-1.1` `V-271572`, `/etc/audit/rules.d/audit.rules`:

```
ContainsLine:           -w /var/log/tallylog -p wa -k logins
DoesNotContainPattern:  #\s*-w\s*/var/log/tallylog\s*-p\s*wa\s*-k\s*logins
```

The `ContainsLine` separators are **non-breaking spaces (U+00A0)**, not spaces. Verified in the raw
processed XML, so this is upstream data and not an artefact of extraction.

Against a host line that also uses U+00A0, `\s`:

- **.NET matches** — its `\s` is `[\f\n\r\t\v\x85\p{Z}]`, and U+00A0 is `Zs`.
- **py-bytes does not match** — a bytes pattern's `\s` is `[ \t\n\r\f\v]`, ASCII only, and U+00A0
  encodes as `\xc2\xa0`.
- **py-str matches** — Unicode-aware again.

So this single pattern behaves differently under the `lineinfile` that ships today than it does
under .NET, and differently again under `lineinfile` on `devel`.

Practical impact on the *pattern* is small: it only bites if the host's file already contains
U+00A0, which a working `audit.rules` would not. The far bigger problem in the same rule is the
`ContainsLine`, which is what `lineinfile`'s `line:` will write: **the generated role would write
non-breaking spaces into `/etc/audit/rules.d/audit.rules`**, and `augenrules`/`auditctl` will
reject that line. That is an upstream data defect worth an issue against PowerStig, and worth a
guard or at least a known-defect test on our side. Flagged to the map.

No other rule in the three products carries a non-ASCII character in either field, apart from
V-257779's newlines (Finding 8).

## Finding 4 — 266 of 282 patterns are wholly unanchored, and `lineinfile` searches

The ticket lists "anchors" among the constructs present. They barely are:

- **6** distinct patterns (11 rules) use `^`.
- **15** distinct patterns (25 rules) use `$`.
- **266** distinct patterns use neither.
- **275** distinct patterns begin with a literal `#` and no `^`.

Because `lineinfile` uses `re.search`, an unanchored pattern matches **anywhere in the line**,
while every STIG check text these came from reads as "the line is commented out" — i.e. `#` in
column one. Worked example, RHEL-9 `V-257989` /
`#\s*Ciphers\s*aes256-gcm@openssh.com,aes256-ctr,…`:

| host line | matches? | should it? |
|---|---|---|
| `Ciphers aes256-gcm@openssh.com,…` (compliant) | no | no |
| `#Ciphers aes256-gcm@openssh.com,…` (commented out) | yes | yes |
| `X=1   # Ciphers aes256-gcm@openssh.com,…` | **yes** | no — trailing comment on an unrelated setting |
| `Ciphers foo  # Ciphers aes256-gcm@openssh.com,…` | **yes** | no — and this is the *last* match, so it wins |

This is not a .NET-vs-Python difference — .NET's `Regex.IsMatch` is equally unanchored, and both
engines agree on all four rows. It is a difference between what the pattern says and what the
check text means, and it arrives intact from PowerStig. It is only reachable through a line with
an embedded `#`, which in most of these config files is uncommon; it is recorded because "anchored
in a way `lineinfile` would apply differently from how the STIG's check text reads" is half the
ticket, and this is the answer to that half.

Anchoring the emitted `regexp` — wrapping as `^…` — would be the converter changing the STIG's
regex. Worth a deliberate decision on the build ticket rather than a silent choice either way.

## Finding 5 — no pattern matches its own target line, and none collides with another rule's

Two checks that could each have produced a mis-edit, both clean:

- **Self-match: 0 of 396.** No `DoesNotContainPattern` matches its own `ContainsLine`. The pattern
  and the desired line are genuinely disjoint.
- **Cross-rule collision: 0.** For every pair of rules targeting the same file in the same
  product, no rule's pattern matches the line another rule wants present. So one task in the
  generated role cannot clobber the line a sibling task just wrote.

Self-match being zero raises an idempotency question that is worth answering explicitly, because
the obvious reading is wrong. On an already-compliant host the pattern matches nothing — but
`lineinfile` then runs its exact-line pass (lines 362–366), finds the compliant line byte-equal to
`line`, sets `index[0]`, and falls through to `elif b_lines[index[0]] != b_new_line`, which is
false. **No change, no duplicate.** The generated tasks are idempotent. Just not for the reason
the `regexp` suggests.

## Finding 6 — a compliant-but-differently-spaced line gets a duplicate appended

The corollary of Finding 5, and the sharpest operational edge found. The exact-line fallback is
**byte equality**. The pattern only matches the commented form. So a host that is compliant but
spells the line differently falls through both:

```
wanted  : Ciphers aes256-gcm@openssh.com,aes256-ctr,…
on host : Ciphers   aes256-gcm@openssh.com,aes256-ctr,…      (three spaces — still compliant)
```

`regexp` does not match it. Exact-line comparison fails. `lineinfile` **appends a second
`Ciphers` line at EOF**, leaving the file with two — and for `sshd_config`, where first-wins, the
appended line is the one that does not take effect. The task reports `changed` forever.

This applies to all 275 `#`-prefixed patterns, which is nearly the whole population. It is
inherent to modelling `DoesNotContainPattern` as `regexp`, not to the port, and it is the strongest
argument the research turned up for the build ticket to consider a `regexp` derived from the
*setting key* rather than PowerStig's commented-form pattern. Flagged to the map.

## Finding 7 — two patterns are valid regex that mean something other than they read

Identical in both engines, so they port fine; recorded because they will read as bugs later.

**`OracleLinux-8-2.4` `V-248538.a` and `V-248539.a`** —
`#\s*set\s*superusers\s*=\s*"[someuniqueUserNamehere]"`. The `[…]` is a **character class**, so it
matches exactly one character drawn from `someuniqUrNmh`:

| line | matches |
|---|---|
| `# set superusers = "root"` | no |
| `# set superusers = "r"` | **yes** |
| `#set superusers="a"` | **yes** |
| `# set superusers = "[someuniqueUserNamehere]"` (literal) | no |

The placeholder was meant literally and the brackets should have been escaped. Both rules also
carry the placeholder in `ContainsLine`, so both are presumably org-value candidates upstream that
PowerStig did not mark as such. Harmless in practice — no real `grub.cfg` has a one-character
superuser — but it will never match the thing it was written to match.

**`OracleLinux-9-1.1` `V-271597`** — `\s*active\s*=\s*no|active=yes|#\s*active\s*=.*` against
`ContainsLine: active = yes`. Two problems, both from the missing `^`:

| line | matches | note |
|---|---|---|
| `active = yes` | no | the compliant line, correctly not matched |
| `active=yes` | **yes** | also compliant — but the second alternative matches it, so the task rewrites a compliant line |
| `inactive = no` | **yes** | `\s*` matches empty, so this hits mid-word |
| `force_active = no` | **yes** | same |

The `active=yes` alternative appears to be an authoring slip: it asserts the *compliant* value is a
violation. The effect is benign — the line gets rewritten to `active = yes`, which is the same
setting — but it means the task is `changed` on a host that was already compliant.

## Finding 8 — one rule's `ContainsLine` is 13 lines, which `lineinfile` cannot express

`RHEL-9-2.8` `V-257779`, `/etc/issue`, the DoD login banner. Its `ContainsLine` contains 12
embedded newlines. `lineinfile` inserts **one** line; handing it a multi-line `line:` writes the
literal text with newlines in it and the `regexp` — which is searched per line — can never match
the banner as a unit.

Out of scope for this ticket and not a regex issue, but it is a rule the `nxFileLine` generator
cannot emit a correct `lineinfile` task for at all. `ansible.builtin.copy` with `content:` is the
shape that fits. Flagged to the map as a new ticket.

## What this means for the generator

1. The port itself needs no translation layer. Emit `DoesNotContainPattern` into `regexp`
   verbatim. Do not escape, re-anchor or normalise it as a general policy.
2. Decide what to do about the 3 uncompilable patterns before the role can run (Finding 2).
3. Decide whether `regexp` should be anchored, knowing that not anchoring is what PowerStig wrote
   and that `re.search` is what will apply it (Finding 4).
4. V-271572's non-breaking spaces and V-257779's 13-line banner are rules the generator cannot
   emit correctly regardless of the regex decision (Findings 3, 8).
5. Do not set `firstmatch`. Last-match-wins is `lineinfile`'s default and nothing here needs
   otherwise; but note it is *last*, which interacts with Finding 4.
6. `\w`/`\s`/`\d`/`\b` are ASCII-only today and Unicode-aware on `devel`. Nothing in scope depends
   on either, but a future STIG revision could.

## Sources

- PowerStig processed STIG XML, branch `dev`: `StigData/Processed/RHEL-9-2.8.xml`,
  `OracleLinux-8-2.4.xml`, `OracleLinux-9-1.1.xml`.
- `ansible/ansible`, `lib/ansible/modules/lineinfile.py` at `devel`, `stable-2.19`, `stable-2.18`,
  `stable-2.17`, `stable-2.16`, `stable-2.15` —
  <https://github.com/ansible/ansible/blob/stable-2.19/lib/ansible/modules/lineinfile.py>
- CPython `re` — bytes patterns restrict `\w`, `\s`, `\d`, `\b` to ASCII:
  <https://docs.python.org/3/library/re.html#regular-expression-syntax>
- .NET character classes — `\s` is `[\f\n\r\t\v\x85\p{Z}]`:
  <https://learn.microsoft.com/en-us/dotnet/standard/base-types/character-classes-in-regular-expressions>
- Engines exercised: .NET 10.0.10, CPython 3.14.4.
