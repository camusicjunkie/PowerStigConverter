---
status: accepted
---

# A variable prefix names the product and only a release that distinguishes siblings

`Get-AnsibleVariablePrefix` derives the stem every generated variable is built on from the STIG
name. It had two branches: `^Windows(\w+)-(\d+)(R\d)?` for a Windows product, which drops the word
`Windows` and keeps the release (`WindowsClient-11` → `stig_client_11`, `WindowsServer-2012R2-DC` →
`stig_server_2012r2`), and a default that sanitises the whole name for everything else
(`IISServer-10.0` → `stig_iisserver_10_0`).

The Windows branch demands digits after the dash, so `WindowsDefender-All` and
`WindowsFirewall-All` fell through to the default and produced `stig_windowsdefender_all` and
`stig_windowsfirewall_all` — keeping a word the branch exists to strip, and keeping `All` as though
it were a release. Surfaced while charting map #110, the first map to convert a Windows component
STIG. `FireFox-All` is the third product PowerStig ships whose name ends that way.

## Decision

**A variable prefix carries the product, plus a release only where sibling releases would
otherwise collide. Nothing else.**

**`All` never appears in a prefix.** It is a STIG's *scope* — it covers every release of its
product — not a release of its own, so it has no sibling to be told apart from and contributes
nothing. It is stripped from the STIG name *before* the product is classified, because that
reasoning holds for a Windows component and an application alike:

| STIG name | Prefix |
| --- | --- |
| `WindowsDefender-All` | `stig_defender` |
| `WindowsFirewall-All` | `stig_firewall` |
| `FireFox-All` | `stig_firefox` |

**A Windows component with no release left to name drops the word `Windows`**, through a
`^Windows(\w+)$` arm that the strip now makes reachable. That is the same treatment
`WindowsClient-11` and `WindowsDnsServer-2012R2` already get, and for the same reason: every role a
Windows STIG generates targets a Windows host, so the word distinguishes nothing. Expressed as its
own arm rather than by loosening the release one, because the two answer different questions —
which release, versus no release — and a compound regex covering both leaves `$matches[2]` unset on
half its inputs.

**A prefix is derived, never enumerated.** No lookup table of product name to prefix.

## Alternatives considered

**Keep `stig_windowsdefender_all`**, which the existing test already pinned as an application STIG.
Rejected: it is the same word, `Windows`, kept for Defender and stripped for Client, Server and
DnsServer, and the inconsistency has no reason behind it beyond the branch demanding digits. It is
free to change now — no fixture, no generated role and no adopter exists for any `-All` product —
and expensive after map #110's fixtures land, since a prefix rename renames every variable in every
role already generated from it.

**Drop `Windows` but keep `All`** (`stig_defender_all`). Rejected: it reads as though an
`stig_defender_2022` existed. The release suffix is kept in the Windows branch for exactly one
reason, stopping two real siblings colliding, and `All` is the absence of a version spelled out.

**Drop `All` for Windows components only, leaving `FireFox-All` as `stig_firefox_all`** until
Firefox's own map has Firefox data in front of it. Rejected: it would leave two products whose names
end the same way deriving differently, which reads as an oversight and needs a test pinning the
asymmetry to say otherwise. The reason `All` contributes nothing does not depend on the product
being Microsoft's, so deferring it would only postpone the same answer at the cost of a rename once
a Firefox fixture existed.

**An explicit product-name → prefix table**, regex as fallback. Rejected: a new product would
silently get no prefix until someone remembered to add a row, where derivation gives every product
a defensible one on the day PowerStig ships it.

## Consequences

- Any future `-All` STIG gets a prefix with no edit here, Windows component or not.
- `FireFox-All` is decided here, ahead of the Firefox map that will convert it. That map inherits
  `stig_firefox` rather than choosing it; it is free to revisit this ADR, but not to be surprised by
  it.
- The strip is `-All$`, anchored and requiring the dash, so a product whose own name ends in those
  letters keeps them — `WindowsFirewall` survives to become `stig_firewall`. The test asserting no
  prefix carries `All` has to look for `_all` rather than `all` for exactly that reason.
- `stig_defender` no longer names its STIG file, so a reader tracing `stig_defender_213450_*` back
  to `WindowsDefender-All-2.8.xml` goes through the role's `meta/main.yml` description rather than
  the variable name. The same is already true of `stig_client_11` and `WindowsClient-11-2.7.xml` —
  no prefix has ever carried a revision.

Decided in [#112](https://github.com/camusicjunkie/PowerStigConverter/issues/112).
