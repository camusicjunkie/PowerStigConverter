# V-253263's version check: what the STIG requires and what `-le` means

Research for [#209](https://github.com/camusicjunkie/PowerStigConverter/issues/209), under the map
[#204](https://github.com/camusicjunkie/PowerStigConverter/issues/204). The question came from
[#195](https://github.com/camusicjunkie/PowerStigConverter/issues/195), which read PowerStig's
`Version -le 10.0.22621` as a minimum mistakenly written as a maximum. No code under `Source/` or
`tests/` was changed.

Sources, read on 2026-10-22:

- PowerStig `dev` @ [`efa8aec`][stig] (2026-06-19). The DISA XCCDF files it converts from are
  checked in under `source/StigData/Archive/Windows.Client/`, so the check and fix text below is
  quoted from DISA's own benchmark files, not from a third-party viewer.
- AuditSystemDsc 1.1.0, the version the lab bootstrap installs, read from the PSGallery package
  ([gallery][asd-gallery]). Its old `microsoft/AuditSystemDsc` GitHub repository no longer
  resolves, so the package is the source.
- This repo's `Source/Private/Task/Build-AnsibleAuditSettingTask.ps1` on `main`.

## Answer

PowerStig's data is right. `-le` is a floor, not a ceiling, because AuditSystemDsc puts the
desired value on the **left** of the operator. The task the converter generates already enforces
"build 22621 or later". The only thing wrong is how this repo labels the task. It reads the
fields in the opposite order from the resource. No rule correction is needed, so the premise of
[#210](https://github.com/camusicjunkie/PowerStigConverter/issues/210) does not hold for this rule.

## 1. What DISA requires

`U_MS_Windows_11_STIG_V2R7_Manual-xccdf.xml` (Release 7, benchmark date 01 Apr 2026), rule
`SV-253263r1016364_rule`, STIG ID **WN11-00-000040**, severity high, *"Windows 11 systems must be
maintained at a supported servicing level."*

> Check: Run "winver.exe".
> If the "About Windows" dialog box does not display "Microsoft Windows 11 Version 22H2 (OS Build
> 22621.380)" or greater, this is a finding.
>
> Fix: Update systems on the Semi-Annual Channel to "Microsoft Windows 11 Version 22H2 (OS Build
> 22621.380)" or greater.

V2R6 (`U_MS_Windows_11_STIG_V2R6_Manual-xccdf.xml`) has the same rule revision and the same text.
It is a **minimum** only: build 22621 (22H2) or later. There is no upper bound and no LTSC
exception list (Windows 11 LTSC 2024 is build 26100, which is above the floor anyway).

One limit of the automated check: `Win32_OperatingSystem.Version` is `10.0.<build>` with no update
revision, so the `.380` half of "22621.380" cannot be tested this way. Only the build is.

## 2. Where PowerStig's `-le 10.0.22621` comes from

`source/Module/Rule.AuditSetting/Convert/AuditSettingRule.Convert.psm1:35-58`
([link][stig-conv]): every check that mentions `winver\.exe` becomes an AuditSetting rule with
`Query = 'SELECT * FROM Win32_OperatingSystem'`, `Property = 'Version'`, and a **hard-coded**
`Operator = '-le'`. `DesiredValue` is `10.0.` plus the first number after "Build" in the check
text. For V-253263 that gives `10.0.22621`. That is exactly what `WindowsClient-11-2.7.xml:1017-1035`
and `WindowsClient-11-2.6.xml` hold.

The operator used to be `-ge`. PowerStig commit [`a7a47f9`][stig-flip] (Brian Wilhite, 2019-08-14)
changed it to `-le` in the converter, its integration tests, and the processed Windows 10 and
Server 2012 R2/2016 data. The commit fixed [microsoft/PowerStig#476][stig-476], *"AuditSetting
Rule for Windows STIGs has an incorrect operator when evaluating Service Pack information"*. The
flip was deliberate. It matches how the DSC resource evaluates the operator (section 3).

## 3. How AuditSystemDsc evaluates it

`AuditSystemDsc/1.1.0/DSCResources/AuditSetting/AuditSetting.psm1`, `Test-TargetResource`,
lines 162-175:

```powershell
foreach ($instance in $queryResult)
{
    $condition = "'$DesiredValue' $Operator '$($instance.$Property)'"
    $isCompliant = [scriptBlock]::Create($condition).Invoke()
```

The desired value is the left operand. For V-253263 the condition the resource runs is
`'10.0.22621' -le '<actual Version>'`, which reads as "the actual version is at least 10.0.22621".
Evaluated in PowerShell 7 here:

| Actual `Version` | `'10.0.22621' -le actual` |
| --- | --- |
| 10.0.26300 (lab VM) | True |
| 10.0.26100 (24H2 / LTSC 2024) | True |
| 10.0.22631 (23H2) | True |
| 10.0.22621 (22H2) | True |
| 10.0.22000 (21H2) | False |
| 10.0.19045 (Windows 10) | False |

So once the resource can load on the client, V-253263 passes on the lab's build 26300. The
`Not found` failure in #195 is the execution-policy problem recorded in that issue's comment, not
this comparison.

Two caveats, both from the comparison being a string comparison, not a `[version]` comparison:

- It is lexical. It holds while builds keep five digits. A six-digit build (`10.0.100000`) would
  compare as lower than `10.0.22621`. Nothing ships that yet.
- The same left-hand order applies to V-253265's `'NTFS|ReFS' -match '<FileSystem>'`. That works
  because the actual value acts as the regex. But a volume whose `FileSystem` is empty matches as
  well, since an empty pattern matches anything. This is outside this ticket's question.

## 4. What this repo does with it

`Source/Private/Task/Build-AnsibleAuditSettingTask.ps1` passes `Query`, `Property`, `DesiredValue`
and `Operator` straight through to `ansible.windows.win_dsc`, so the resource gets PowerStig's
fields unchanged and enforces the floor correctly. The task's name is built as
`'Audit that {0} {1} {2}' -f Property, Operator, DesiredValue`, which gives
`Audit that Version -le 10.0.22621`. That puts the property on the left, the opposite of the
resource, and it is the reading that made #195 suspect the data. A name that follows the
resource's order (for example `Audit that 10.0.22621 -le Version`) would describe what is actually
tested. That is a labelling change in the generator, not a data correction.

## 5. Windows 10 (V-220706 / WN10-00-000040)

- **V3R5** (`U_MS_Windows_10_STIG_V3R5_Manual-xccdf.xml`, benchmark 01 Oct 2025): the same shape
  with a floor of "Version 22H2 (OS Build 19045.x)" or greater. It also says LTSC builds 10240,
  14393, 17763 and 19044 are not a finding. PowerStig's `WindowsClient-10-3.5.xml:997-1016`
  holds `-le 10.0.19045`. That is a correct floor under the resource's operand order, but it
  would wrongly fail those LTSC builds, which the STIG's own exceptions allow.
- **V3R6** (`U_MS_Windows_10_STIG_V3R6_Manual-xccdf.xml`, benchmark 05 Jan 2026, after Windows
  10's 14 Oct 2025 end of support): the check text becomes *"If the 'About Windows' dialog box
  does not display a version supported by the vendor, this is a finding"*. The fix is *"Upgrade to
  a supported version of the operating system."* There is no build number to compare against.
  PowerStig's `WindowsClient-10-3.6.xml:1274` emits it as a `DocumentRule` (`dscresource="None"`),
  and V3R6's conversion log has an entry for it (`V-220706::*::.`). The 3.6 data this repo's
  fixtures use has no AuditSetting rule for V-220706. So there is no version task for Windows 10
  to get wrong, and nothing to carry over to it.

## Consequences for the map

- V-253263 needs no correction in `RuleCorrection.psd1`. #210's question ("may a correction change
  a rule field") has no driver from this rule.
- The task name in `Build-AnsibleAuditSettingTask` misstates the comparison and could be reordered.
  That is a small generator change, if wanted.
- V-253263's lab failure is covered by #195's execution-policy finding.

[stig]: https://github.com/microsoft/PowerStig/tree/efa8aec
[stig-conv]: https://github.com/microsoft/PowerStig/blob/efa8aec/source/Module/Rule.AuditSetting/Convert/AuditSettingRule.Convert.psm1#L35-L58
[stig-flip]: https://github.com/microsoft/PowerStig/commit/a7a47f9a26d56d0c6c6818a79796fc097ad45b8e
[stig-476]: https://github.com/microsoft/PowerStig/issues/476
[asd-gallery]: https://www.powershellgallery.com/packages/AuditSystemDsc/1.1.0
