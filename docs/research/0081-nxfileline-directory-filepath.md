# What does V-258109 intend, given its `FilePath` is a directory?

Research for [#81](https://github.com/camusicjunkie/PowerStigConverter/issues/81), a child of
map [#78](https://github.com/camusicjunkie/PowerStigConverter/issues/78).

Sources are the processed PowerStig XML in the local upstream clone
(`$env:LOCALAPPDATA\PowerStig\source\StigData\Processed`, branch `dev`), the PowerStig converter
source on GitHub (`microsoft/PowerStig`, branch `dev`), and the published STIG text on
stigviewer.com (Red Hat Enterprise Linux 9 STIG, dated 2026-05-20).

## Short answer

The trailing slash is **not** the STIG describing a directory. It is the truncation point of a
shell glob, produced by PowerStig's own `FilePath` regex, and it means the processed XML has
**lost** the path the rule is about rather than recorded it.

For V-258109 the published fix text names the file outright:

> Add or update the following line in the **"/etc/security/pwquality.conf"** file or a
> configuration file in the "/etc/security/pwquality.conf.d/" directory to contain the "ocredit"
> parameter: `ocredit = -1`
>
> — RHEL 9 STIG, V-258109, fix `F-61774r1045219_fix`

So the rule intends `/etc/security/pwquality.conf`. Nothing needs inventing for this rule; the
filename is published, PowerStig simply did not capture it.

And this is not one rule. **26 parsed in-scope `nxFileLine` rules carry a directory-shaped
`FilePath`** (plus one unparsed), across nine distinct directories. Sizing the answer for
V-258109 alone would fix 1 of 26.

## Why the path is a directory

`Get-nxFileLineFilePath` (`source/Module/Rule.nxFileLine/Convert/Methods.ps1`) matches the
check-content against, among others, `$regularExpression.nxFileLineFilePath`
(`source/Module/Rule.nxFileLine/Convert/Data.ps1`):

```
(?:#|\$\s+sudo|#\s+sudo)\s+(?:egrep|grep|cat|more).*\s+(?<filePath>(?!\/etc\/redhat-release)\/[\w.\/-]*\/[\w.\/-]*)
```

Two properties of that expression produce the bug together:

1. **The `.*` before the capture is greedy**, so on a command naming several paths the capture
   binds to the *last* one.
2. **The capture class `[\w.\/-]` does not include `*`**, so a glob terminates the match at the
   character before it.

V-258109's check command is:

```
$ sudo grep ocredit /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf
```

Greedy `.*` skips past `/etc/security/pwquality.conf` — the file the fix text actually names —
and the capture then stops dead at the `*`, leaving `/etc/security/pwquality.conf.d/`. The
trailing slash is the glob's amputation scar.

Every one of the 26 rules has this same shape: a check command that greps a base file plus a
drop-in glob, or a drop-in glob alone.

## The full in-scope population

Surveyed over `//nxFileLineRule/Rule` in `RHEL-9-2.8.xml`, `OracleLinux-8-2.4.xml` and
`OracleLinux-9-1.1.xml`, counting only rules with `dscresource="nxFileLine"` (420 parsed rules
in total). No in-scope `FilePath` is empty, non-absolute, or contains a surviving glob character
— the trailing slash is the only malformed shape.

| Product | Parsed | Directory-shaped |
| --- | ---: | ---: |
| RHEL-9-2.8 | 131 | 10 |
| OracleLinux-8-2.4 | 174 | 14 |
| OracleLinux-9-1.1 | 115 | 2 |
| **Total** | **420** | **26** |

One further rule, OracleLinux-9 `V-271725` (`/etc/sudoers.d/`), is directory-shaped but carries
`dscresource="none"` — already an unparsed rule and already out of scope per #78.

### Group A — the fix text names an exact file (14 rules)

The filename is published; the converter would be quoting the STIG, not asserting anything.

| Rule | Product | `FilePath` in XML | File the fix text names |
| --- | --- | --- | --- |
| V-258039.b | RHEL-9 | `/etc/modprobe.d/` | `/etc/modprobe.d/bluetooth.conf` |
| V-258214 | RHEL-9 | `/etc/audit/rules.d/` | `/etc/audit/rules.d/audit.rules` |
| V-248828.b | OL-8 | `/etc/modprobe.d/` | a file under `/etc/modprobe.d/` (per-module) |
| V-248829.b | OL-8 | `/etc/modprobe.d/` | as above (`atm`) |
| V-248830.b | OL-8 | `/etc/modprobe.d/` | as above (`can`) |
| V-248831.b | OL-8 | `/etc/modprobe.d/` | as above (`sctp`) |
| V-248832.b | OL-8 | `/etc/modprobe.d/` | as above (`tipc`) |
| V-248833.b | OL-8 | `/etc/modprobe.d/` | as above (`cramfs`) |
| V-248834.b | OL-8 | `/etc/modprobe.d/` | as above (`firewire-core`) |
| V-248527 | OL-8 | `/etc/dconf/db/local.d/` | `/etc/dconf/db/local.d/01-banner-message` |
| V-248870 | OL-8 | `/etc/dconf/db/local.d/` | a file under `/etc/dconf/db/local.d/` |
| V-248574 | OL-8 | `/etc/yum.repos.d/` | `/etc/yum.repos.d/[your_repo_name].repo` — a placeholder |
| V-248631.a | OL-8 | `/etc/security/limits.d/` | `/etc/security/limits.conf` or a `limits.d` file |
| V-248631.b | OL-8 | `/etc/security/limits.d/` | as above |

Verified verbatim for V-258039 (`/etc/modprobe.d/bluetooth.conf`), V-258214
(`/etc/audit/rules.d/audit.rules`), V-248527 (`/etc/dconf/db/local.d/01-banner-message`) and
V-248574; the rest follow the same published pattern.

Two of these deserve calling out because they break the "just quote the fix text" story:

- **V-248574 is the one rule where any filename really would be an assertion about the target.**
  The fix text says `/etc/yum.repos.d/[your_repo_name].repo` — a placeholder. The requirement is
  "every `.repo` file on this host sets `gpgcheck=1`", which is a glob over files only the target
  knows. `lineinfile` cannot express it at all; it wants `find` plus a loop, or a `with_fileglob`.
- **V-248527 and V-248870 need an INI section, not just a line.** The fix adds
  `banner-message-enable=true` *to the `[org/gnome/login-screen]` section*, then runs
  `dconf update`. `lineinfile` has no notion of a section; this wants `ansible.builtin.ini_file`
  plus a handler. The directory path is the least of these two rules' problems.

Note that PowerStig already hard-codes exactly this kind of answer elsewhere — the `auditPath`
branch of `Get-nxFileLineFilePath` returns the literal `/etc/audit/rules.d/audit.rules`. It just
does not fire for V-258214, whose check says `cat /etc/audit/rules.d/*` rather than naming
`/etc/audit/audit.rules`.

### Group B — base file plus optional drop-in; the base file is the answer (5 rules)

| Rule | Product | `FilePath` in XML | Base file in the check/fix |
| --- | --- | --- | --- |
| V-258109 | RHEL-9 | `/etc/security/pwquality.conf.d/` | `/etc/security/pwquality.conf` |
| V-271636 | OL-9 | `/etc/security/pwquality.conf.d/` | `/etc/security/pwquality.conf` |
| V-258122 | RHEL-9 | `/etc/sssd/conf.d/` | `/etc/sssd/sssd.conf` |
| V-258133.a | RHEL-9 | `/etc/sssd/conf.d/` | `/etc/sssd/sssd.conf` |
| V-258133.d | RHEL-9 | `/etc/sssd/conf.d/` | `/etc/sssd/sssd.conf` |

V-258122's fix text reads "Edit the file `/etc/sssd/sssd.conf` **or** a configuration file in
`/etc/sssd/conf.d`" — the same base-or-drop-in construction as V-258109. Note also that
V-258109's own `Description` says the credit value "must be expressed as a negative number in
`/etc/security/pwquality.conf`", so even the processed XML contains the right filename — just not
in the `FilePath` field.

### Group C — the rule is broken for reasons beyond the path (7 rules)

These carry check-text **prose** in `ContainsLine`, so they would emit a nonsense `lineinfile`
even with a correct path. Fixing the path does not make them convertible.

| Rule | Product | `FilePath` | `ContainsLine` |
| --- | --- | --- | --- |
| V-258133.b | RHEL-9 | `/etc/sssd/conf.d/` | `If "cache_credentials" is set to "false" or missing…` |
| V-258133.c | RHEL-9 | `/etc/sssd/conf.d/` | `If "cache_credentials" is set to "true", check that…` |
| V-258149 | RHEL-9 | `/etc/rsyslog.d/` | `To check for Rainer script syntax, perform the following: $ sudo grep -rq…` |
| V-258167.c | RHEL-9 | `/var/log/audit/` | `$ sudo find /var/log/audit/ -type f -exec stat -c '%a %n' {} \;` |
| V-248723.b | OL-8 | `/etc/rsyslog.d/` | `If the command does not return a response, check for cron logging…` |
| V-248723.c | OL-8 | `/etc/rsyslog.d/` | `Look for the following entry:` |
| V-271585.c | OL-9 | `/var/log/audit/` | `$ sudo ls -la /var/log/audit/*.log` |

The two `/var/log/audit/` rules are worse still: they are file-*permission* requirements (audit
logs must be mode 0600) typed as `nxFileLine`. There is no line to add to any file, and the
directory is a log directory, not configuration.

**This prose problem is bigger than the directory problem.** Across all 420 in-scope parsed
rules, **35** carry a `ContainsLine` that is check-text prose rather than a configuration line
(RHEL-9: 12, OL-8: 12, OL-9: 11). Only 7 of those overlap with the directory-shaped set. That
is a separate defect needing its own ticket.

## The candidates, and what each costs

### 1. Pick a conventional drop-in filename

Cost: for Group A and Group B this is **not inventing anything** — the filename is in the
published fix text, or in the rule's own `Description`. But it is not in the `FilePath` field the
generator is handed, so implementing it means either a lookup table in this repo keyed by rule ID,
or re-parsing prose. A lookup table is 19 hand-maintained entries that go stale every time DISA
reissues a STIG, and it is this module doing PowerStig's job — the same reasoning #78 used to put
unparsed rules out of scope.

For rules where no file is named — the OL-8 `modprobe.d` entries, and V-248574 whose fix text
literally says `[your_repo_name]` — choosing one *would* be asserting a fact. For `modprobe.d` it
is a mild assertion, about a file the task itself creates; for V-248574 it is a real one, about
which repositories the target has.

This option also does not rescue every rule even when it works. V-248527 and V-248870 need an INI
section and a `dconf update`, and V-248574 needs a glob over unknown files; a correct `path` on a
`lineinfile` still leaves those three wrong.

### 2. Emit nothing and warn

Cost: 26 real requirements silently uncovered — 6% of the in-scope corpus, including
`ocredit`, SSSD smart-card auth, and seven kernel-module blacklists. But it is honest, it is one
code path, it scales to whatever the next STIG revision produces, and the warning names the rules
so the gap is visible rather than assumed away.

### 3. Treat it as an unparsed rule

Cost: none that option 2 does not also carry, and it buys consistency. #78 already established
"unparsed rule" as the name for a rule PowerStig could not parse and already put those out of
scope with their own workflow. A `FilePath` that is a truncated glob is precisely a rule
PowerStig could not parse — it just failed silently, writing a plausible-looking wrong value
instead of `dscresource="none"`.

## Recommendation

**Option 3, with option 2's warning as the mechanism: treat a `FilePath` ending in `/` as
unconvertible, skip it, and warn naming the rule.** Then raise it upstream.

Three reasons:

1. **ADR 0005 is about not asserting facts, and a trailing slash is a missing fact, not a
   present one.** The ADR's principle is that the path is emitted as the STIG wrote it. Here the
   STIG did not write this path — PowerStig manufactured it by truncating a glob. Emitting it
   would not be honouring the rule; it would be emitting a value the rule never contained. A
   `lineinfile` pointed at a directory fails at runtime anyway, so there is no version of
   "emit it as-is" that works.

2. **The guard is needed regardless.** #78 already records that `Build-AnsibleNxFileLineTask`
   must guard unparsed rules explicitly or emit `lineinfile` with an empty `path`. A directory
   `FilePath` is the same class of input hitting the same guard. One predicate — "is this
   `FilePath` something `lineinfile` can act on?" — covers both, and the same guard catches the
   Group C prose rules if the predicate also asks whether `ContainsLine` looks like a
   configuration line.

3. **The fix belongs upstream and is small there.** Making the `nxFileLineFilePath` regex
   non-greedy, or teaching it to prefer the first path when a glob truncates the last, would fix
   most of these 26 rules at the source for every consumer. PowerStig's own `auditPath` special
   case shows the project already accepts hard-coded answers of this kind. Upstream releases
   roughly quarterly, so a fix could land inside the module's own cadence, and the skip-and-warn
   path degrades gracefully to zero rules when it does.

The cost that argues against this — 26 uncovered requirements — is real and should be recorded on
the map rather than glossed. But it is 26 rules uncovered *and named*, versus 19 filenames this
repo would have to own and keep current for the rest of the module's life.

## Loose ends worth their own tickets

- **35 rules carry check-text prose in `ContainsLine`.** Larger than the path problem, same
  class of silent mis-parse, and it hits rules whose `FilePath` is perfectly well formed. Needs
  its own guard and its own sizing.
- **An upstream issue on `microsoft/PowerStig`** for the greedy `nxFileLineFilePath` regex,
  citing V-258109 as the clearest case.
- **Two `/var/log/audit/` rules are permission requirements mis-typed as `nxFileLine`.** Even a
  perfect `nxFileLine` generator cannot express them. Worth noting on the map as permanently
  uncoverable through this rule type.
- **Three OL-8 rules need a module other than `lineinfile`.** V-248527 and V-248870 want
  `ansible.builtin.ini_file` plus a `dconf update` handler; V-248574 wants a file glob. They are
  uncovered by the skip-and-warn recommendation for a reason unrelated to the path, and would stay
  uncovered even if upstream fixed the regex tomorrow.
