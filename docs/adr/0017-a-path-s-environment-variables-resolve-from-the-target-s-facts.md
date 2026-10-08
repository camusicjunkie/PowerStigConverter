---
status: accepted
---

# A path's environment variables resolve from the target's facts

ADR 0005 stopped `Build-AnsiblePermissionTask` expanding a path's `%Var%` on the converting
machine, and emitted the path as the STIG wrote it on the grounds that `win_acl` expands
environment variables on the target itself. It does not. `win_acl` checks the path with
`Test-Path -LiteralPath` and fails with `%SystemDrive%\ file or directory does not exist on the
host`. The first run of a generated role against a real Windows Server 2025 host failed 48 of its
Permission tasks that way, every one whose path held `%windir%`, `%ProgramFiles%`,
`%ProgramFiles(x86)%` or `%SystemDrive%`.

ADR 0005's rule still stands: a generator reads the rule and nothing else. What it got wrong is
which side expands the variable, not whether the converting machine may.

## Decision

**The role resolves a path's `%Var%` on the target from its gathered facts.** The Windows
scaffolding's `tasks/main.yml` sets one fact, `<prefix>_env`, before any generated task runs: the
target's `ansible_facts['env']` with every name lowercased. `Build-AnsiblePermissionTask` rewrites
each `%Var%` in the path as `{{ <prefix>_env['var'] }}`.

**Names are lowercased on both sides.** Windows ignores the case of a variable's name and STIGs
vary it: current Windows 10 and 11 STIGs spell `%Windir%` where Server 2025 spells `%windir%`, and
the target reports `windir`. A fact dictionary is case-sensitive, so looking the STIG's spelling up
directly would miss. Lowercasing both sides means any variable resolves, with no table of
canonical names to maintain.

## Considered options

- **A lookup in each path.** A case-insensitive `dict2items | selectattr` expression per path
  needs no scaffolding change, but repeats a long expression in every Permission task.
- **A table of canonical names in the generator.** The shortest output, but a variable missing
  from the table would still fail on the target.

## Consequences

- The task's `name` keeps the path as the STIG wrote it, so a role still reads in the STIG's own
  terms. Its `path` is the expression `win_acl` actually receives.
- A role depends on facts being gathered. It already did: its first task asserts the OS from them.
- The Linux scaffolding sets no `<prefix>_env`. Permission is the only rule type that reads it,
  and it targets Windows (ADR 0010).
- Another generator that meets a `%Var%` resolves it through the same fact rather than inventing
  its own.

Supersedes the `win_acl` expansion claim in [ADR-0005](0005-a-rule-s-path-is-emitted-as-the-stig-wrote-it.md).
