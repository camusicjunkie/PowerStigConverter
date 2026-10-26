---
status: accepted
---

# A STIG profile is the only parser of a STIG's name

"Which STIG is this, and what kind of host does it describe?" was answered by regexes over three
identities, in at least seven modules:

- **the STIG name:**
  - `Get-AnsibleOsAssertion`, `Get-AnsibleVariablePrefix` and `Get-AnsibleRoleName`, each with its
    own regexes;
  - `Build-AnsibleAccountPolicyTask`, twice, by `-DC$`;
  - `Build-AnsibleWindowsFeatureTask`, by `^WindowsClient-`;
- **the XML's `stigid`:** `Get-AnsibleIisScope`, by `IIS_.+_Server`;
- **the processed file's base name:** corrections are keyed by it.

Every adapter took both `$StigName` and `$StigId`, and every naming function took `$StigName` only
to recompute the variable prefix. A STIG name nothing recognised fell through to "a Windows
application, any release", which `Ubuntu-18.04` did too.

Three modules add domain-membership conditions:

- dispatch, from NA-off-a-domain wording (ADR 0026);
- the UserRight split (ADR 0025);
- AccountPolicy's member gate (ADR 0027).

They were reconciled only by exact-string de-duplication, so a requirement could be gated both on
and off a domain and never run.

## Decision

**`Get-PowerStigProfile` builds a STIG profile** (see `CONTEXT.md`) from a STIG name, revision and
`stigid`. `Import-PowerStigData` builds it once and carries it on the loaded STIG. It answers:

- the product and revision;
- the OS family and major version, and the OS assertion (pattern, description);
- the target: domain controller, member server or client;
- the IIS scope: server or site;
- the variable prefix and the default role name.

It absorbs the three functions above, with their logic unchanged.

**Nothing else parses a STIG name or `stigid`.** Adapters take `($Rule, $StigProfile, $Resolution)`.
Dispatch, the exporters, the naming functions, the scaffold and `Get-AnsibleIisScope` take the
profile and ask it. A test greps `Source/` for a regex applied to a STIG name or `stigid` outside
the builder. (`$StigProfile`, not `$Profile`, which is PowerShell's automatic variable.)

**A products table.** `StigProduct.psd1` maps every product (the STIG name's first part) to what the
name does not spell out: its OS family, and for Windows clients the target. A product it doesn't
list fails the conversion, naming the table. A test fails when downloaded STIG data has a product
missing from it, as ADR 0021 guards its own table. Ubuntu is left out: there is no converter for it.

**`-StigName` is matched exactly** against a downloaded STIG's name (#237), so the profile is
parsed from a name that is known to exist.

**A requirement that would run only on and off a domain at once fails the conversion**, naming the
STIG and rule. The fix is a `RuleCorrection.psd1` entry (ADR 0020).

## Alternatives considered

**Profile the target only, and keep naming in its own functions.** Rejected: adapters took
`$StigName` mostly to build variable names, so most callers would still have re-parsed the name.

**Add the profile beside `$StigName` and `$StigId`.** Rejected: two ways to ask the same question,
and nothing stops the old one from coming back.

**Keep the fallthrough for an unknown product.** Rejected: it guessed Windows for Ubuntu.

## Consequences

- ADRs 0007, 0010, 0012, 0013 and 0019 name `Get-AnsibleOsAssertion`, `Get-AnsibleVariablePrefix`
  and `Get-AnsibleRoleName`. Their decisions stand; the logic now lives in `Get-PowerStigProfile`.
- A new product is one line in `StigProduct.psd1`. A new kind of target, or a product whose OS
  assertion needs its own rule, is a change to `Get-PowerStigProfile` alone.
- Tests build a profile with `New-TestStigProfile`, or let `Invoke-Generator` build one from a
  STIG name and `StigId`.

Decided in [#238](https://github.com/camusicjunkie/PowerStigConverter/issues/238).
