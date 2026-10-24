---
status: accepted
---

# A rule the STIG marks NA off a domain runs only on a domain member

Some Windows rules say in their check text that they do not apply to a host outside a domain. The
generated role applied them anyway. On a workgroup host the token-filter rule (V-253357 on
Windows 11, V-254429 on Server 2022 MS) then set `LocalAccountTokenFilterPolicy` to 0 and cut
Ansible's WinRM connection, though the STIG marks it NA there (#151).

## Decision

**Dispatch reads the rule's `RawString` for DISA's NA-off-a-domain wording**, and when it finds it
ANDs `ansible_facts['windows_domain_member']` after the rule's `_when` toggle. That is the fact and
the `when` merge ADR 0025 already uses. `Get-AnsibleApplicabilityCondition` holds the wording:

- `If the system is not a member of a domain, this is NA` (or `Not Applicable`)
- `... standalone [or nondomain-joined] systems, this is NA` (or `not applicable`), which covers
  the client STIGs' `applicable to domain-joined systems` and the member-server STIGs'
  `For domain controllers and stand-alone or nondomain-joined systems`

It is dispatch's job, not a generator's, because it is the same for every rule type. A standalone
task carries the condition in its `when` list, a block carries it beside its toggle, and an
organization-value assert takes it along with the toggle. A block's sub-rules share their base
rule's check text, so the first one speaks for the block. A condition a generator already set on a
standalone task (ADR 0025's domain-only user right, Windows 11's V-253492) is not repeated. Where
ADR 0025's split leaves both lists (Windows 10's V-220969 and V-220970), the `users` expression
still checks domain membership; on a task already gated on it that check always holds, which is
redundant but harmless.

**Wording that misstates where a rule applies is corrected in `RuleCorrection.psd1`** with a
`ReplaceInRawString` entry (ADR 0020), not by widening the pattern.

**Wording that says a rule is NA for domain controllers alone is ignored.** The DC and MS STIGs are
separate files, so a member-server STIG is never applied to a DC.

**A test reads PowerStig's fetched data** and fails when a converted rule's line mentions NA beside
a domain but is neither wording above nor a DC-versus-member-server split. A new phrasing therefore
fails the suite rather than leaving its rule applied on a workgroup host.

## Alternatives considered

**A list of rule ids per STIG revision**, in `RuleCorrection.psd1` or a file of its own. Rejected for
the reason ADR 0025 rejected one: it needs an entry per rule per revision, and DISA's wording is
fixed enough for one pattern to cover every revision, with the data test catching what it misses.

**A pattern with a per-rule override.** Rejected until a rule needs one: no rule in the fetched data
says one thing and means another.

## Consequences

- The workgroup lab hosts skip these rules; only a domain member exercises them.
- The pattern reads prose. A line that means NA off a domain but reads as a DC-versus-member-server
  split slips past both the pattern and the data test, and its rule applies off a domain as before.
- The data test reads one line at a time, and only where PowerStig's data has been fetched, so CI
  without it relies on dispatch's tests of the known wording.
- A generator's own domain condition inside a block is not deduplicated against the block's; no
  grouped rule sets one today.
- ManualRule and DocumentRule entries with the same wording (Server 2025 MS's V-278178, #227)
  produce no task, so nothing is conditioned for them until they convert.

Decided in [#226](https://github.com/camusicjunkie/PowerStigConverter/issues/226).
