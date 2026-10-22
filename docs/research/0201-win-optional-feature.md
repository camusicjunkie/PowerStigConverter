# What `win_optional_feature` needs from a WindowsFeature rule

Research for [#206](https://github.com/camusicjunkie/PowerStigConverter/issues/206), under the map
[#204](https://github.com/camusicjunkie/PowerStigConverter/issues/204); the originating bug is
[#194](https://github.com/camusicjunkie/PowerStigConverter/issues/194). No code under `Source/` or
`tests/` was changed.

Sources, read on 2026-10-22:

- ansible.windows `main` @ [`5814722`][aw]. `win_optional_feature.ps1` and `.py` are identical to
  tag `3.8.0` ([`ff0ac96`][aw380]), the version the lab runs (`git diff 3.8.0 HEAD` is empty for
  both files). Line numbers below hold for both.
- PowerStig `dev` @ [`efa8aec`][stig], `source/StigData/Processed/WindowsClient-10-3.6.xml` and
  `WindowsClient-11-2.7.xml`.
- Microsoft Learn: [Disable-WindowsOptionalFeature][ms-disable], [Detect, enable, and disable
  SMBv1][ms-smb], [Available features on demand][ms-fod]; Microsoft Support
  [KB5065506 PowerShell 2.0 removal][ms-ps2].

Local experiments were read-only `Get-WindowsOptionalFeature -Online` / `Get-WindowsCapability
-Online` queries on the converting workstation (Windows 11 26H2, build 10.0.26300, the same build
as the `stig-win11` lab VM in #194), under both Windows PowerShell 5.1.26100 and PowerShell 7.6.6,
with `$ErrorActionPreference = 'Stop'`. No feature was enabled or disabled, and the lab VM was not
touched.

## 1. Parameters: the same words as `win_feature`

[`win_optional_feature.ps1:8-16`][aw-spec] declares:

| option | type | default | notes |
| --- | --- | --- | --- |
| `name` | `list` of `str`, required | | passed to `-FeatureName` |
| `state` | `str`, `absent` / `present` | `present` | |
| `source` | `str` | | `present` only |
| `include_parent` | `bool` | `false` | `present` only, maps to `-All` |

[`win_feature.ps1:10-19`][aw-wf] has `name` (list of str, required) and `state` (`present` /
`absent`, default `present`) with the same spellings. So the body `Build-AnsibleWindowsFeatureTask`
emits today (`name: <Rule.Name>`, `state: absent|present`) is valid for `win_optional_feature`
unchanged; only the module key differs. Neither `source` nor `include_parent` is needed for any
client rule, since every one wants the feature absent (§4).

The module supports check mode (`supports_check_mode = $true`, line 15).

## 2. A feature name the OS does not ship

The module first fails if `Enable-WindowsOptionalFeature` is missing at all — *"This version of
Windows does not support the Enable-WindowsOptionalFeature."* ([lines 27-29][aw-cmd]). Every
Windows 10/11 has the DISM module, so that branch is not the one a client hits.

For each name it calls `Get-WindowsOptionalFeature -Online -FeatureName $feature_name` and, if
nothing comes back, calls **`FailJson("Failed to find feature '$feature_name'")`** ([lines
32-42][aw-find]). This check runs for both states, *before* the state is compared, so `state:
absent` with an unknown name fails rather than reporting "already absent".

- The collection's own integration test pins the exact message:
  `failed_when: invalid_name.msg != "Failed to find feature 'FakeFeature'"`
  ([tests.yml:19-25][aw-it]).
- Locally, `Get-WindowsOptionalFeature -Online -FeatureName FakeFeature` (and
  `MicrosoftWindowsPowerShellV2`, see §4) returns `$null` **without** an error record under
  `-ErrorAction Stop`, on both 5.1 and 7.6, so execution does reach `FailJson`, not an unhandled
  exception. The `COMException` catch (lines 36-39) is for Server 2012 only.
- Because the message comes from `FailJson`, it is in the registered result's `.msg`, as #146's
  tolerance expects.
- With a list of names, the loop fails on the first unknown one before anything is changed
  (lines 32-52). The generator emits one name per task, so this does not matter today.

**Consequence for #146's tolerance:** `'is not valid'` is `win_feature`'s (Server Manager's) wording
and will not match. The `win_optional_feature` equivalent is the substring `'Failed to find
feature'`, i.e.

```yaml
failed_when: <reg> is failed and 'Failed to find feature' not in (<reg>.msg | default(''))
```

## 3. Reboots

- The module always calls the cmdlets with `-NoRestart` ([lines 69 and 80][aw-act]) and returns
  `reboot_required` set from the cmdlet's `RestartNeeded` (default `$false`, line 25). It never
  reboots by itself; the documented pattern is to follow with `win_reboot` when
  `reboot_required` ([.py EXAMPLES][aw-doc]).
- `Disable-WindowsOptionalFeature` outputs `Microsoft.Dism.Commands.ImageObject`, and
  `-NoRestart` "suppresses reboot. If a reboot is not required, this command does nothing"
  ([Microsoft Learn][ms-disable]).
- A feature already in a `Disabled*` state (`Disabled`, `DisabledPending`,
  `DisabledWithPayloadRemoved`) is skipped ([lines 47-50][aw-find]): no cmdlet call, `changed:
  false`, `reboot_required: false`. So reboots only arise on the run that actually removes it.
- **SMB1Protocol:** Microsoft says "The computer restarts after you run the PowerShell commands to
  disable or enable SMBv1" ([SMBv1 doc][ms-smb]); with `-NoRestart` that becomes
  `reboot_required: true`. SMBv1 is not installed by default on any Windows 11 edition or on
  Windows 10 since 1709 except Home and Pro (same page), so on a STIG baseline this task is
  usually a no-op.
- **PowerShell V2:** no Microsoft source states whether disabling it needs a restart, and it could
  not be tested here because this build no longer ships it (§4). `Get-WindowsOptionalFeature`
  reports `RestartRequired = Possible` for every feature queried, which is not specific.
  Not established; the module's `reboot_required` is the authority at run time.

Whether the generated role should act on `reboot_required` is the "client prerequisites" question
still open on #204; this note only records that the module reports it and does not reboot.

## 4. Are PowerStig's client names optional-feature names?

PowerStig's processed data ([`efa8aec`][stig]); every rule is `Ensure=Absent`,
`dscresourcemodule="PSDscResources"`:

| STIG | rule | `Name` | `dscresource` | on 10.0.26300 |
| --- | --- | --- | --- | --- |
| WindowsClient-11-2.7 | V-253277 | `SimpleTCP` | `WindowsFeature` | optional feature, Disabled |
| WindowsClient-11-2.7 | V-253285.a | `MicrosoftWindowsPowerShellV2` | `WindowsFeature` | **not offered** |
| WindowsClient-11-2.7 | V-253285.b | `MicrosoftWindowsPowerShellV2Root` | `WindowsFeature` | **not offered** |
| WindowsClient-11-2.7 | V-253286 | `SMB1Protocol` | `WindowsFeature` | optional feature, Disabled |
| WindowsClient-10-3.6 | V-220718.a | `IIS-HostableWebCore` | `WindowsOptionalFeature` | optional feature, Disabled |
| WindowsClient-10-3.6 | V-220718.b | `IIS-WebServer` | `WindowsOptionalFeature` | optional feature, Disabled |
| WindowsClient-10-3.6 | V-220719 | `SNMP` | `WindowsOptionalFeature` | **not offered** (it is a capability) |
| WindowsClient-10-3.6 | V-220720 | `SimpleTCP` | `WindowsOptionalFeature` | optional feature, Disabled |
| WindowsClient-10-3.6 | V-220721 | `TelnetClient` | `WindowsOptionalFeature` | optional feature, Disabled |
| WindowsClient-10-3.6 | V-220722 | `TFTP` | `WindowsOptionalFeature` | optional feature, Disabled |
| WindowsClient-10-3.6 | V-220728.a | `MicrosoftWindowsPowerShellV2` | `WindowsOptionalFeature` | (Windows 10 still ships it; see below) |
| WindowsClient-10-3.6 | V-220728.b | `MicrosoftWindowsPowerShellV2Root` | `WindowsOptionalFeature` | (as above) |
| WindowsClient-10-3.6 | V-220729 | `SMB1Protocol` | `WindowsOptionalFeature` | optional feature, Disabled |

The last column is the Windows 11 workstation; there is no Windows 10 host to query (#204 rules a
Windows 10 VM out of scope).

- **Names are optional-feature names**, with the exceptions below. They are the exact
  `FeatureName`s the STIG check text itself uses: V-253285's check runs
  `Get-WindowsOptionalFeature -Online | Where FeatureName -like *PowerShellv2*` and names both
  `MicrosoftWindowsPowerShellV2` and `...V2Root`; V-253286's runs
  `Get-WindowsOptionalFeature -Online | Where FeatureName -eq SMB1Protocol` (rule `RawString`).
  Microsoft's SMBv1 page uses `-FeatureName SMB1Protocol` too ([SMBv1 doc][ms-smb]).
- **PowerShell 2.0 is gone from Windows 11 24H2 and later.** Microsoft removed it "starting in
  August 2025 for Windows 11, version 24H2" (and September 2025 for Server 2025) ([KB5065506][ms-ps2]).
  Both names return nothing on this 26H2 build, so on the `stig-win11` lab VM both V-253285 tasks
  will fail with `Failed to find feature 'MicrosoftWindowsPowerShellV2'` unless tolerated (§2).
  The STIG agrees: V-253285's check text opens "For Windows 11 version 24H2 and newer, this
  requirement is Not Applicable." This is the same situation as #146 on Server 2025.
- **SNMP is not an optional feature on any current Windows 10.** Since Windows 10 1809 it is the
  Feature on Demand `SNMP.Client~~~~0.0.1.0` ([Available features on demand][ms-fod]), managed by
  `Get-/Add-/Remove-WindowsCapability`, not `*-WindowsOptionalFeature`. Locally,
  `-FeatureName SNMP` returns nothing and `Get-WindowsCapability -Online -Name SNMP*` lists
  `SNMP.Client~~~~0.0.1.0 NotPresent`. So V-220719 would always hit
  `Failed to find feature 'SNMP'`; with the tolerance it passes as "not offered", which is only
  right if the capability is also absent. ansible.windows does have a module for it,
  `win_capability` (`name` list, `state: absent|present`, built on `Get-WindowsCapability`; present
  in 3.8.0 and at [`5814722`][aw-cap]). Whether V-220719 should be routed there, or its `Name`
  corrected in `RuleCorrection.psd1` (ADR 0020), is a separate decision.
- **PowerStig's `dscresource` is inconsistent across the two products**: Windows 10 says
  `WindowsOptionalFeature`, Windows 11 says `WindowsFeature`, for the same names. PSDscResources'
  `WindowsFeature` is the Server Manager resource, so the Windows 11 value is wrong in the same way
  `win_feature` was. As #194 already notes, the generator should decide from the product (the
  rule's own data, ADR 0005), not from this attribute.

## Answers to #206

1. **Parameters:** `name` (list of str) and `state: absent|present` (default `present`), the same
   words as `win_feature`. The existing task body works with only the module key changed.
2. **Unknown name:** `failed: true`, `msg: "Failed to find feature '<name>'"`, for `absent` as well
   as `present`. Match `'Failed to find feature'`, not `'is not valid'`.
3. **Reboot:** never reboots (`-NoRestart`); returns `reboot_required` from DISM's `RestartNeeded`,
   only on a run that changes something. Removing SMB1Protocol requires a restart per Microsoft;
   PowerShell V2's was not established.
4. **Names:** all are optional-feature names except `SNMP` (a capability since Windows 10 1809).
   `MicrosoftWindowsPowerShellV2` / `...V2Root` are no longer shipped on Windows 11 24H2+,
   including the lab VM, so they need the tolerance.

[aw]: https://github.com/ansible-collections/ansible.windows/tree/5814722
[aw380]: https://github.com/ansible-collections/ansible.windows/tree/3.8.0
[aw-spec]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_optional_feature.ps1#L8-L16
[aw-cmd]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_optional_feature.ps1#L27-L29
[aw-find]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_optional_feature.ps1#L31-L52
[aw-act]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_optional_feature.ps1#L55-L84
[aw-doc]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_optional_feature.py
[aw-it]: https://github.com/ansible-collections/ansible.windows/blob/5814722/tests/integration/targets/win_optional_feature/tasks/tests.yml#L19-L25
[aw-wf]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_feature.ps1#L10-L19
[aw-cap]: https://github.com/ansible-collections/ansible.windows/blob/5814722/plugins/modules/win_capability.ps1#L9-L19
[stig]: https://github.com/microsoft/PowerStig/tree/efa8aec/source/StigData/Processed
[ms-disable]: https://learn.microsoft.com/en-us/powershell/module/dism/disable-windowsoptionalfeature
[ms-smb]: https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3
[ms-fod]: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod
[ms-ps2]: https://support.microsoft.com/help/5065506
