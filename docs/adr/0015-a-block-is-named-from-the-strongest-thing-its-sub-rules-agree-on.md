---
status: accepted
---

# A block is named from the strongest thing its sub-rules agree on

A requirement needing several tasks becomes one block, titled `<base id> | <SEVERITY> | <block
detail>`. Each generator returns that detail per rule, and `Set-AnsibleGroupTaskName` assembled
the group's from the union of the distinct values its sub-rules produced — decided at ADR 0009 for
`nxFileLine`, whose sub-rules genuinely edit different files.

`WindowsFirewall-All-2.2` broke the union. Three of its eighteen sub-rule pairs write one value
into two keys whose leaves are two spellings of one profile: the policy key under
`SOFTWARE\Policies\Microsoft\WindowsFirewall` calls it `PrivateProfile`, the live service key
under `SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy` calls the same
profile `StandardProfile`. The union named it `V-241990 | MEDIUM | PrivateProfile,
StandardProfile`, reading as a requirement covering two profiles where it covers one.

ADR 0009 justified the union partly on Registry's premise of sub-rules sharing one key, so
Registry's own naming was decided nowhere. Surveying all 133 registry sub-rule groups upstream
settled what the fields actually do:

| | groups | reads |
| --- | --- | --- |
| key leaves agree | 117 | the leaf names the location the requirement configures |
| leaves differ, `ValueName` shared | 6 (Firewall ×3, WindowsClient-10 V-220835 / -11 V-253394) | **union is false** — one value, two locations |
| leaves differ, `ValueName` differs | 10 | union is true — IE V-223071, SqlServer-2016 V-213967, SqlServer-2022 V-271310, whose five leaves are `SSL 2.0`/`SSL 3.0`/`TLS 1.0`/`TLS 1.1`/`TLS 1.2` |

Firewall is not the outlier the surfacing ticket took it for: `WindowsClient-10` and `-11` already
ship a block named `Config, DeliveryOptimization` for `DODownloadMode`, carrying the same
falsehood parent-key to child-key rather than sibling to sibling. And `ValueName` is the *least*
stable field across registry sub-rules, not the most — 83 of the 133 groups disagree on it, and
SqlServer-2022 V-271310's `ValueName` is a sentence of check prose PowerStig failed to parse.

## Decision

**A generator offers the candidates its sub-rules might agree on, strongest first; the block is
named from the strongest candidate every sub-rule agrees on, and from the union of their
strongest where they agree on none.** `GroupDetail` becomes an ordered candidate list; a bare
string is one candidate, so every generator that had nothing to prefer is unchanged.

`Registry` offers `@($keyLeaf, $Rule.ValueName)`: the leaf for the 117 groups that share one, the
`ValueName` for the 6 that write it into two differently-spelled locations, the union of leaves
for the 10 that genuinely span several keys and values. Every case on current data reads as the
requirement rather than as a list of registry locations.

**A candidate counts as agreed only when every sub-rule offers one at that rank and all are
equal.** A member offering fewer candidates than another cannot agree at a rank it does not
reach, and an empty candidate is no agreement — both fall through to the next rank.

**Per-requirement naming is the default; a per-sub-rule detail that relies on the union is the
exception, and the exceptions are named.** `nxFileLine` offers the file leaf, because its
sub-rules genuinely touch different files (ADR 0009). `Build-AnsibleRootCertificateTask` offers
the certificate name, because its sub-rules genuinely name several certificates. Those two are the
list; a third has to justify itself rather than reach for the union by default, which is how
Firewall's false name arose. `Build-AnsibleSqlDatabaseTask` already chose this way before the
union existed — `Ensure` alone, the only field its `.a`-`.d` share.

**The agreement test is structural, never a synonym table.** `PrivateProfile` and
`StandardProfile` are never recognised as the same profile; the generator only observes that the
halves agree on `EnableFirewall` and disagree on where they write it, and names the block from
the agreement. Nothing is read out of the STIG's prose and no mapping is invented, per ADR 0005.

## Alternatives considered

**Keep the union.** Rejected: it is the behaviour #119 exists to correct, false for 6 of 133
groups across three products, in two different ways.

**Name a block from the `.a` leaf alone**, since the policy key is what the STIG text is written
against. Rejected: stable by construction, but it silently drops the rest of a requirement that
genuinely spans several keys — `V-271310 | HIGH | SSL 2.0` for a rule covering five protocol keys
is a worse falsehood than the one being fixed, and it asks a generator to know which half of a
pair is canonical, which is true of Firewall and unverified anywhere else.

**Name a registry block from `ValueName` unconditionally.** Rejected on the data: 83 of 133 groups
disagree on it, so most blocks would become unions of value names — Firefox V-252881 would read
`Cache, Cookies, Downloads, FormData, History, Locked, OfflineApps, Sessions, SiteSettings` — and
the field carries unparsed prose on one product.

**Branch the union on rule type in `Set-AnsibleGroupTaskName`.** Rejected: `ConvertTo-AnsibleTask`
owns everything every rule type does the same way and branches on type nowhere, by its own
contract. A candidate list expresses the same preference through what the adapter returns, which
is where a per-type judgement belongs.

## Consequences

- `WindowsClient-10-3.6` and `-11-2.7` generate `V-220835 | LOW | DODownloadMode` and
  `V-253394 | LOW | DODownloadMode` in place of `Config, DeliveryOptimization` — confirmed by
  converting the untrimmed upstream data for both — without their fixtures changing, since
  neither fixture's trim kept the rule. Proving it there would mean adding a
  pair to two closed maps' fixtures, the cost ADR 0014 weighed and declined for the 206 `Absent`
  rules; the same answer applies. Firewall's fixture carries the shape end to end, and the
  branches themselves are covered where the logic lives.
- The union fallback has no end-to-end coverage: it is reachable only from Internet Explorer and
  SqlServer, and the SqlServer-2016 fixture's trim happens to have kept two halves sharing
  `Client`. Unit tests on `Set-AnsibleGroupTaskName` cover it directly.
- A block name is descriptive only — a block's `when` comes from the base id, never from its name
  — so no generated role's behaviour changes, only what an operator reads.
- `Get-AnsibleBlockDetail` is the one place a block is named. A rule type wanting different
  behaviour changes the candidates it offers, not this function.
- The code calls the concept `GroupDetail`, alongside `GroupId` and `Group-AnsibleTask`, while
  `CONTEXT.md` calls it **block detail**. Renaming the three to match is a sweep of its own and is
  deliberately not done here.

Decided in [#119](https://github.com/camusicjunkie/PowerStigConverter/issues/119).
