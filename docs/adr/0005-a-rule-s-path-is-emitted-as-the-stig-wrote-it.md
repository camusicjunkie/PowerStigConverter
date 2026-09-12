---
status: accepted
---

# A rule's path is emitted as the STIG wrote it

`Build-AnsiblePermissionTask` decided the path it wrote into the role by asking the **converting**
machine whether the expanded path existed:

```powershell
$parsedPath = [System.Environment]::ExpandEnvironmentVariables($Rule.Path)
$path = if (Test-Path $parsedPath) { $parsedPath } else { $Rule.Path }
```

So the same STIG produced `C:\Windows\System32\config` when converted on a machine where that
directory existed and `%SystemRoot%\System32\config` when converted anywhere else. The role
differed by who generated it, and neither answer was about the **target** — the only machine whose
filesystem the rule is about. A STIG writes `%SystemRoot%` precisely because the answer belongs to
the target, and `win_acl` expands environment variables there itself.

The path is now emitted exactly as the rule carries it. `Test-Path` and
`ExpandEnvironmentVariables` leave the generator, which no longer reads anything outside the rule
it was handed.

## Consequences

- A rule converts to the same task wherever it is converted. This is the general rule, not a fact
  about permissions: **a task generator reads the rule and nothing else.** No generator may consult
  the converting machine's filesystem, environment or registry to decide what it emits, because the
  machine that runs the conversion is not the machine the rule describes.
- The task's `name` carries the raw path too, so a role reads the way it runs rather than naming a
  path different from the one `win_acl` acts on.
- Generated output moves for any Permission rule whose path holds an environment variable. No
  fixture on `main` carried one when this was decided, so no fixture changed. A fixture that does
  carry one will record the raw path.
- A path that needs resolving on the converter — if one ever does — is a different problem from
  this one, and wants an organization value or a role variable rather than a `Test-Path` at
  conversion time. See [ADR-0003](0003-every-organization-value-is-a-role-variable.md).

Decided in [#8](https://github.com/camusicjunkie/PowerStigConverter/issues/8).
