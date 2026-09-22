# UserRight "nobody holds this right" survey for issue #101

Research for [#101](https://github.com/camusicjunkie/PowerStigConverter/issues/101). Scope: how a
`UserRight` rule's `Identity` field reaches the generated `win_user_right` task when it means
"nobody should hold this right," and what every real `<UserRightRule>` in the locally cached
upstream PowerStig processed STIG data actually says. No code under `Source/` or `tests/` was
changed to produce this - it is a fact-finding pass only; the fix is a separate ticket.

## 1. How the field reaches the task today

- `Source\Files\OrganizationData.psd1:26-34` - the `UserRight` entry maps `'Value' = 'Identity'`,
  `'List' = @('Identity')` (so the resolved value is always split into a list, for
  `win_user_right`'s `users:` parameter), and `'Empty' = 'NULL'` - "PowerStig spells 'nobody holds
  this right' as the string NULL" (comment on line 33).
- `Source\Private\Resolve-AnsibleOrganizationValue.ps1:144` -
  `elseif ($data['Empty'] -and $Rule.($data['Value']) -eq $data['Empty']) { @() }` - this is the
  only branch that returns an empty list. It fires **only** when `$Rule.Identity` is the exact
  string `'NULL'` (a string `-eq` comparison, not `[string]::IsNullOrEmpty`).
- When that comparison fails - which includes every case where `Identity` is blank, an
  empty/whitespace-only string, or a self-closing element - control falls through to
  `Resolve-AnsibleOrganizationValue.ps1:146-148`:
  ```
  elseif ($data['List'] -contains $data['Value']) {
      , ($Rule.($data['Value']) -split ',')
  }
  ```
  `'' -split ','` returns a one-element array holding an empty string (`@('')`), and the leading
  comma (there to stop PowerShell unrolling a genuine single-element list back to a scalar on
  return, per the comment on line 145) preserves that shape rather than collapsing it. The
  resolved `.Value` is therefore `@('')`, not `@()`.
- `Source\Private\Task\Build-AnsibleUserRightTask.ps1:18` - `'users' = $Resolution.Value` passes
  that array straight into the `ansible.windows.win_user_right` task body with no further
  filtering. A blank-`Identity` "nobody" rule with `OrganizationValueRequired: False` therefore
  generates `users: ['']` instead of `users: []`.
- This branch is reached only when `OrganizationValueRequired` is `False`
  (`$decidedByOrganization` at line 40 is false, so the `elseif ($decidedByOrganization)` arm at
  line 128 is skipped, and the `Enabled|Disabled` arm at line 129 does not match `Identity`
  values). When `OrganizationValueRequired` is `True`, a blank `Identity` on the rule is
  irrelevant - the value comes from the org settings node instead, a separate question this
  survey does not need to resolve.
- Runtime confirmation: traced by reading, not executed (no code was run against
  `Resolve-AnsibleOrganizationValue.ps1` for this survey), but the code path above is
  unconditional and unambiguous - there is no other branch that could intercept a blank
  `Identity` before the `List` split.

## 2. What the existing test covers

`tests\Resolve-AnsibleOrganizationValue.Tests.ps1`:

- No test constructs a rule with `Identity = 'NULL'` or asserts the `@()` branch at all - a
  repo-wide search for the literal `'NULL'` in the test file returns no matches.
- No test constructs a rule with a blank/empty `Identity` and `OrganizationValueRequired = False`
  either. The closest cases are the list-shape tests (lines 220-276):
  - Line 222-233: `Identity = 'Administrators,Authenticated Users'` splits into two entries.
  - Line 237-249: `Identity = 'Administrators'` stays a one-element list, not a scalar.
  - Line 251-263: an unrelated `IisLogging` single-value-list case.
  - Line 265-275: `Identity = ''` with `OrganizationValueRequired = $true` - this is the
    *organization-decides* path (`$reference[...]`, a `{{ variable }}` string), not the
    `Empty`/`List`-split path this survey is about, and it asserts a variable reference, not a
    list shape.
- Net: the `Empty`/`NULL` "nobody holds this right" branch, and the blank-`Identity` fallthrough
  it is supposed to catch, have zero direct test coverage today.

## 3. Inventory of every `<UserRightRule>` with a NULL-or-blank `Identity` in the cached upstream data

Surveyed `%LOCALAPPDATA%\PowerStig\source\StigData\Processed\*.xml` (148 files, every product
PowerStig ships). A recursive search for `<UserRightRule` returns exactly 20 files, all Windows
products - Windows Client 10/11, Windows Server 2016/2019/2022/2025, and Windows DNS Server
2012R2. No other product family (SQL Server, IIS, RHEL, Oracle Linux, Ubuntu, browsers, Office,
Adobe, etc.) has a `UserRightRule` element anywhere in the corpus, so this is a Windows-only
concern as expected.

Each `<UserRightRule>` wraps one or more `<Rule id="...">` children carrying `<Identity>`,
`<IsNullOrEmpty>` (a boolean PowerStig itself already computes - present on every `UserRightRule`
`<Rule>`, though nothing in `Source\` currently reads it), and `<OrganizationValueRequired>`.
Across the 20 files, 125 `<Rule>` elements have an `Identity` that is either the literal string
`NULL` or blank/whitespace-only:

| Identity form | Count | Files | OrganizationValueRequired |
|---|---|---|---|
| Literal `NULL` | 12 | `WindowsServer-2016-DC-2.9.xml`, `WindowsServer-2016-MS-2.9.xml` only (6 rules each) | `False` for all 12 |
| Blank/self-closing | 113 | all other 18 files with `UserRightRule` | `False` for 96, `True` for 17 |

The `False`-only 96 blank rows are the ones that actually reach the buggy `List`-split
fallthrough today (`OrganizationValueRequired: True` rows resolve through the org-decides branch
instead, a separate code path). The 12 literal-`NULL` rows all have
`OrganizationValueRequired: False` too, and are the only rows the current `Empty`/`NULL` branch
catches.

Representative rows (full detail, file:line citations into the cached XML):

- `WindowsServer-2016-DC-2.9.xml:6796-6807`, rule `V-225070` ("Access Credential Manager as a
  trusted caller"): `<Identity>NULL</Identity>`, `<IsNullOrEmpty>False</IsNullOrEmpty>`,
  `<OrganizationValueRequired>False</OrganizationValueRequired>`.
- `WindowsServer-2016-DC-2.10.xml:6807-6820`, the **same rule id** `V-225070` one STIG revision
  later: `<Identity>\n      </Identity>` (blank/whitespace), `<IsNullOrEmpty>True</IsNullOrEmpty>`,
  `<OrganizationValueRequired>False</OrganizationValueRequired>` - otherwise byte-for-byte
  identical `<Description>`/`<Constant>`/`<DisplayName>`/`<RawString>` content. This is direct
  evidence that PowerStig changed its own "nobody holds this right" spelling for the identical
  rule between STIG revisions 2.9 and 2.10 of the same product, from the literal string `NULL`
  to a blank element - and flipped its own `IsNullOrEmpty` flag accordingly.
- All 6 `V-2250xx` rules in `WindowsServer-2016-DC-2.9.xml` / `WindowsServer-2016-MS-2.9.xml`
  (`V-225002`, `V-225070`, `V-225071`, `V-225077`, `V-225085`, `V-225091` for DC;
  `V-225020`, `V-225070`, `V-225071`, `V-225077`, `V-225085`, `V-225091` for MS) carry the literal
  `NULL`; their identical successors in `-2.10.xml` carry a blank `<Identity>` instead.
- Every other product/version (`WindowsClient-10-3.5/3.6`, `WindowsClient-11-2.6/2.7`,
  `WindowsDnsServer-2012R2-2.5/2.7`, `WindowsServer-2019-DC-3.7/3.8`,
  `WindowsServer-2019-MS-3.7/3.8`, `WindowsServer-2022-DC-2.7/2.8`,
  `WindowsServer-2022-MS-2.7/2.8`, `WindowsServer-2025-DC-1.1`, `WindowsServer-2025-MS-1.1`) uses
  a blank `<Identity>` exclusively for its "nobody" rules - never the literal `NULL`.

PowerStig's own `IsNullOrEmpty` flag correlates perfectly with the semantic "nobody holds this
right" question, once `OrganizationValueRequired` is accounted for:

| Identity | OrganizationValueRequired | Rows | `IsNullOrEmpty` = `True` |
|---|---|---|---|
| blank | `False` | 96 | 96 / 96 |
| blank | `True` | 17 | 0 / 17 |
| literal `NULL` | `False` | 12 | 0 / 12 (PowerStig's own flag checks string emptiness, and the string `NULL` is not empty) |

A blank `Identity` with `OrganizationValueRequired: True` is not a "nobody" statement at all - it
is an unanswered organization value pending a settings file, a different question this resolver
already handles correctly via the `$decidedByOrganization` branch.

## 4. Findings

### Should blank/`IsNullOrEmpty` be recognized as "nobody holds this right" alongside the literal `NULL`?

Yes. The data confirms blank `Identity` combined with `OrganizationValueRequired: False` means
exactly the same thing PowerStig spells as literal `NULL` elsewhere - the `V-225070` case is
direct proof, since the identical rule (same STIG ID, same wording, same `Constant`) flips from
`NULL` to blank between STIG revisions 2.9 and 2.10 of `WindowsServer-2016-DC`/`-MS` with no
change in intent. PowerStig's own `IsNullOrEmpty` field, already present on every `UserRightRule`
`<Rule>` element in the cached corpus (though never read anywhere in `Source\` today), correlates
1:1 with this: every one of the 96 blank+`OrganizationValueRequired:False` rows has
`IsNullOrEmpty: True`, and none of the 17 blank+`OrganizationValueRequired:True` rows do (blank
there means "pending an org answer," not "nobody"). Recognizing
`[string]::IsNullOrEmpty($Rule.Identity)` (or reading `$Rule.IsNullOrEmpty` directly) alongside
the literal-`NULL` check would correctly route all 96 currently-mishandled rows to `@()` without
touching the 17 organization-decided rows, which never reach this branch in the first place.

### Should the literal-`NULL` branch be kept at all, given how narrow its real-world footprint is?

The issue's claim is confirmed exactly: the literal string `NULL` appears in a `UserRightRule`
`Identity` in exactly two files across the whole 148-file cached corpus -
`WindowsServer-2016-DC-2.9.xml` and `WindowsServer-2016-MS-2.9.xml` (12 rules total, 6 per file) -
and nowhere else, including every other revision of every other Windows product surveyed. Both
files are the immediately-superseded `2.9` revision of a product now shipping `2.10`
(`WindowsServer-2016-DC-2.10.xml` / `WindowsServer-2016-MS-2.10.xml` are both present in the same
cache and use blank `Identity` for the identical rules). Per this repo's own scoping convention
("a retired STIG is the exclusion test, not an EOL OS" - the STIG *revision*, here, not just the
OS), `2.9` is superseded but this survey did not check DISA's current-vs-retired revision listing
to confirm `2.9` itself has been formally withdrawn - that check is out of scope for this pass.
Regardless of retirement status, the branch's practical footprint in the cache today is exactly
those 12 rows out of 125 candidates (roughly 10%), all concentrated in one already-superseded
revision pair.

Given that the blank-`Identity` recognition above needs to be added regardless, and would on its
own already correctly handle every row the literal-`NULL` branch currently handles (`NULL` fails
`[string]::IsNullOrEmpty`, so the two checks are not the same condition and would need to coexist,
*or* the fix could normalize both spellings into one check, e.g.
`$Rule.($data['Value']) -eq $data['Empty'] -or [string]::IsNullOrEmpty($Rule.($data['Value']))`).
Dropping the literal-`NULL` branch outright would break the 12 rows in the `2.9` files if that
revision is still shipped and converted from; keeping both checks (or folding `NULL` recognition
into a combined blank-or-`NULL` predicate) costs nothing and preserves backward compatibility with
any cached or offline STIG data still using the older convention. The narrow footprint argues for
*simplifying* the two checks into one combined condition, not for deleting `NULL` recognition
entirely.
