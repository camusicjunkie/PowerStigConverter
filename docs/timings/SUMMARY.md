# Per-task timing from existing lab runs

Source: the 18 `ansible.log` files under `lab/.local/*/runs/` (log_path timestamps; a task's duration is the gap to the next TASK line). Parser: `Measure-TaskTiming.ps1` here (`-LogRoot` points at the run logs). Output: `rules.csv` (per run, per V-id), checked in; `tasks.csv` (3,890 tasks) is regenerated and gitignored.

- Full runs take ~2,400-3,300 s (40-55 min) for 280-450 tasks.
- 394 of 446 tasks in the full ws2025 run take 2-10 s: per-task WinRM overhead, not slow rules.
- 587 distinct rules: 450 reach 5 s, 102 reach 10 s, 23 reach 20 s, 14 reach 30 s, 9 reach 60 s, 5 reach 120 s (each rule's slowest run).
- Rules at or above 60 s are almost all `Permission` rules on broad roots (one task per principal, each ~50-300 s): `%windir%` (V-278000 / V-254253), `%SystemDrive%\` (V-277998 / V-254251), `%ProgramFiles%` (V-277999 / V-254252), HKLM registry ACLs (V-278001 / V-254254), NTDS (V-278138).
- Those rules are ~1,000 s of the 3,216 s ws2025 run (32%) and ~1,800 s of the 3,117 s DC run (58%).
- Per-task time varies 2x between runs of the same rule (e.g. 85 s vs 150 s for the `%windir%` ACLs). Take ranges, not single values.
- Rules between 20 and 60 s are a mixed tail: more ACLs, registry one-offs, the NTFS audit (13-36 s), firewall/defender sets (~10-25 s).
