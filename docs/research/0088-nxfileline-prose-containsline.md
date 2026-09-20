# How big is the `ContainsLine`-is-prose population, and how much of it is recoverable?

Research for [#88](https://github.com/camusicjunkie/PowerStigConverter/issues/88), a child of
map [#78](https://github.com/camusicjunkie/PowerStigConverter/issues/78), sizing a problem
surfaced while resolving [#81](https://github.com/camusicjunkie/PowerStigConverter/issues/81).
That ticket's own resolution comment claimed **35 of 420 parsed in-scope `nxFileLine` rules carry
check-text prose in `ContainsLine` instead of a line to write** (RHEL-9 12, OL-8 12, OL-9 11).
This ticket verifies that population, classifies it, and checks recoverability — it does not
decide what the `nxFileLine` generator (design ticket
[#83](https://github.com/camusicjunkie/PowerStigConverter/issues/83)) should do about any of it.

Source: the processed PowerStig XML in the local upstream clone
(`$env:LOCALAPPDATA\PowerStig\source\StigData\Processed\{RHEL-9-2.8,OracleLinux-8-2.4,OracleLinux-9-1.1}.xml`,
branch `dev`, verified 2026-09-20), and the PowerStig converter source
(`microsoft/PowerStig`, branch `dev`, `source/Module/Rule.nxFileLine/Convert/Methods.ps1`) for how
`DoesNotContainPattern` is generated.

## Short answer

**35 rules confirmed, exact match to #81's claim and its per-product breakdown**
(RHEL-9-2.8: 12, OracleLinux-8-2.4: 12, OracleLinux-9-1.1: 11). A mechanical predicate — a
keyword/pattern scan over `ContainsLine` — recovers this population with only **one** false
positive requiring manual judgment, and a broadened recheck of the remaining 361 non-empty
rules found no misses. **9 of the 35 are recoverable** from `RawString` (the real line is quoted
literally there); the other **26 are not recoverable from any field on the rule** — most (16) are
file-permission/ownership checks mistyped as `nxFileLine`, where no line was ever the answer.
`DoesNotContainPattern` carries the identical prose on all 35, but only because PowerStig
generates it mechanically *from* `ContainsLine` by regex-escaping it — it is the same defect
appearing twice, not an independent one.

## Population — 420 parsed, 24 org-value rules excluded, 35 confirmed

Surveyed `//nxFileLineRule/Rule` in the three latest-revision files, `dscresource="nxFileLine"`
only (matches #81's 420):

| Product | Parsed | Empty `ContainsLine` (org-value) | Non-empty | Prose (this ticket) |
| --- | ---: | ---: | ---: | ---: |
| RHEL-9-2.8 | 131 | 6 | 125 | 12 |
| OracleLinux-8-2.4 | 174 | 15 | 159 | 12 |
| OracleLinux-9-1.1 | 115 | 3 | 112 | 11 |
| **Total** | **420** | **24** | **396** | **35** |

The 24 empty-`ContainsLine` rules are a *different*, already-handled mechanism: every one has
`OrganizationValueRequired="True"` — PowerStig leaves `ContainsLine` blank because the real value
is filled in from the organization's answer, which is what `Resolve-AnsibleOrganizationValue`
already exists to do (see `docs/adr/0004`). They are not part of the 35 and not in scope here.

## The predicate — mostly mechanical, one hand-classified exception

`ContainsLine` matching any of these (case-insensitive) reliably separates check-text prose from
a real config line:

```
\bfinding\b | \bcheck\b | \bverify\b | \$\s*sudo | \bcommand\b | ^\s*if\b | \blook for\b | \bfollowing\b
```

Applied to the 396 non-empty rules this returns **36** matches. One is a false positive:
**V-257779** (RHEL-9, the DoD login banner) — its `ContainsLine` *is* legitimately the multi-line
banner text `/etc/issue` must contain; it only matches because the banner's own wording says
"...you consent to the **following** conditions". Excluding it by hand gives exactly 35, split
12/12/11 across the three products — the same numbers #81 reported.

A second, broader pass over the remaining 361 non-flagged rules (additional keywords —
`determine`, `note:`, `indicates`, `does not`, `will return`, `ensure`, `perform`, `substitute`,
or ContainsLine over 20 words) turned up **only V-257779 again**, no new misses. So: **mechanical
predicate, with a one-rule, well-understood manual exception** — not a per-rule manual list.

## Classification by shape

| Shape | Count | Recoverable? |
| --- | ---: | --- |
| File permission/ownership check mistyped as `nxFileLine` (`stat`/`ls` on `/var/log/audit*` or `auditd.conf` config-location lookups) | 16 | No |
| SSSD `cache_credentials` conditional branch text | 4 | No |
| Descriptive "how to check" prose with no literal answer stated (rsyslog cron logging, Rainer syntax, faillock SELinux context, SHA_CRYPT rounds, umount audit rule) | 5 | No |
| `pam_faillock` config line glued to trailing check-text prose | 5 | Yes — real line is in `RawString`, cleanly separated |
| `sudo` reauthentication timestamp check | 2 | Yes — `RawString` quotes `Defaults timestamp_timeout=0` verbatim |
| rsyslog TLS offload setting | 1 | Yes — `RawString` quotes `$ActionSendStreamDriverMode 1` verbatim |
| Bluetooth kernel-module blacklist | 1 | Yes — `RawString` quotes `"blacklist bluetooth"` verbatim |
| **Total** | **35** | **9 recoverable / 26 not** |

### Recoverable — 9

| Rule | Product | `ContainsLine` (truncated) | Recovered value | Where |
| --- | --- | --- | --- | --- |
| V-248670.a–.e | OL-8 | `auth required pam_faillock.so preauth dir=... Check the security context type...` | `auth required pam_faillock.so preauth dir=/var/log/faillock` / `authfail dir=/var/log/faillock` (two lines) | `RawString` |
| V-258084 | RHEL-9 | `If results are returned from more than one file location, this is a finding.` | `Defaults timestamp_timeout=0` | `RawString` |
| V-271722 | OL-9 | (same wording) | `Defaults timestamp_timeout=0` | `RawString` |
| V-248816 | OL-8 | `$ sudo grep -i '$ActionSendStreamDriverMode' ...` | `$ActionSendStreamDriverMode 1` | `RawString` |
| V-248843.a | OL-8 | `Verify the operating system disables the ability to use Bluetooth...` | `blacklist bluetooth` | `RawString` (quoted as the expected output) |

`Description` never contributes a recovery for any of the 35 — every recoverable value came from
`RawString`, where the check command's expected output is quoted for a human to compare against.
`Description` on these rules is the STIG's `<VulnDiscussion>` boilerplate (why the control
matters), not the control's mechanics.

### Not recoverable — 26, two concrete examples

- **V-258167.c (RHEL-9)** / **V-271585.c (OL-9)** and 14 siblings: `ContainsLine` is literally a
  `stat`/`ls` invocation (`$ sudo find /var/log/audit/ -type f -exec stat -c '%a %n' {} \;`). The
  requirement is "audit logs must be mode 0600" — a file-permission fact, not a line any file
  should contain. No field on the rule holds a line, because there never was one; `nxFileLine`
  is the wrong DSC resource for this STIG requirement (`ansible.builtin.file` mode would be
  the correct target). Confirms #81's note that these are permission checks mistyped as
  `nxFileLine`, and shows the mistyping extends to more rules (16) than #81 sized (which only
  flagged the 2 with a directory-shaped `FilePath` too).
- **V-258133.b / V-258133.c (RHEL-9)**, **V-271609.b / V-271609.c (OL-9)**: SSSD
  `cache_credentials` is a two-branch conditional ("if false, not a finding"; "if true, check a
  different thing") — there is no single line whose presence proves compliance, so nothing in
  `RawString` or `Description` names one. The real config directive is
  `offline_credentials_expiration = 1`, but it never appears verbatim in the rule; inferring it
  requires STIG-writer intent, not data recovery.

## `DoesNotContainPattern` — same shape, but as a downstream effect

`Get-nxFileLineDoesNotContainPattern` in `microsoft/PowerStig`
(`source/Module/Rule.nxFileLine/Convert/Methods.ps1`, `dev`) does not parse
`DoesNotContainPattern` from the check text independently. It takes `ContainsLine` and
regex-escapes it (spaces → `\s*`, `=` → `\s*=\s*`, prefixed with `#\s*`) to build the pattern a
commented-out line would match. Confirmed against the XML: every one of the 35 rules'
`DoesNotContainPattern` values are exactly that transform applied to the prose `ContainsLine` —
e.g. V-248535's `ContainsLine` `If only one of "SHA_CRYPT_MIN_ROUNDS" or "SHA_CRYPT_MAX_ROUNDS"
is set...` becomes `DoesNotContainPattern`
`#\s*If\s*only\s*one\s*of\s*"SHA_CRYPT_MIN_ROUNDS"\s*or\s*"SHA_CRYPT_MAX_ROUNDS"\s*is\s*set,...`.

So: **yes, the identical prose shape appears in `DoesNotContainPattern` on all 35 rules** — but
it is not a second, independent mis-parse. It is the same `ContainsLine` defect propagating
through PowerStig's own derivation, one input field feeding one derived field. There is no rule
in the 420 where `DoesNotContainPattern` is prose while `ContainsLine` is not, and no case where
`DoesNotContainPattern` is independently wrong. A fix to `ContainsLine` (upstream, or a recovery
this repo applies) would automatically fix `DoesNotContainPattern` for the same rule.

## Summary for the design ticket (#83)

- Population is confirmed at 35, not an estimate — verified by full XML scan plus a broadened
  recheck for misses.
- A predicate exists and is cheap: the keyword/pattern scan above, no per-rule table needed,
  with one well-understood exception (the DoD banner rule, which is legitimate and must not be
  excluded by the same predicate used to flag prose — see below).
- 9 of 35 have their real line sitting in `RawString`, recoverable by extracting the token(s) the
  STIG's own check output quotes — worth a design conversation. Whether that extraction belongs
  in this converter is out of scope for this ticket.
- 26 of 35 are not recoverable at all; 16 of those are file-permission checks that were never
  representable as `nxFileLine` in the first place, regardless of any fix to `ContainsLine`
  parsing.
- `DoesNotContainPattern` needs no separate handling — whatever guard or fix addresses
  `ContainsLine` prose covers it for free.

### One caution for whatever predicate #83 designs

The keyword scan used here is a *detection* tool tuned for manual review, not a validated
generator-time guard. It has one known false positive (V-257779, the legitimate long banner
text) in the current data, and it has not been proven to have zero false positives against
future STIG revisions or other rule types. A generator-time predicate should be re-validated
against whatever the design settles on, not lifted verbatim from this ticket.
