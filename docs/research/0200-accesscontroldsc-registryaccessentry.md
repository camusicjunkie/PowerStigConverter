# AccessControlDsc `RegistryAccessEntry` invocation for issue #200

Research for [#200](https://github.com/camusicjunkie/PowerStigConverter/issues/200). Scope: how
AccessControlDsc's `RegistryAccessEntry` resource expects to be called, which `Inheritance` values
it actually accepts, and whether `ansible.windows.win_dsc` or `Invoke-DscResource` can drive it.
The question came from trying the resource for the `HKLM:\SECURITY` DACL rule (V-253431). No code
under `Source/` or `tests/` was changed. The fix #200 shipped took a different route (ADR 0023).

Sources are pinned to the commits read on 2026-10-21:

- AccessControlDsc `Dev` @ [`1c4d77c`][acd]. Its RegistryAccessEntry `.psm1`, `.schema.mof` and
  both examples are byte-identical to the PSGallery 1.4.3 package (diffed, CRLF ignored), and `Dev`'s
  manifest still says `ModuleVersion = '1.4.3'`. Line numbers below hold for both.
- ansible.windows `main` @ [`5814722`][aw]. `win_dsc.ps1` was last changed in `8c0a361` (2021-12-01).
- ansible `devel` @ [`01a2851`][ab] for `Ansible.Basic.cs`.
- PowerShell `master` @ [`2150ca1`][pwsh]; PSDesiredStateConfiguration 2.0.7 from PSGallery.
- PowerStig `dev` @ [`efa8aec`][stig].
- MicrosoftDocs/PowerShell-Docs-DSC @ [`992e0ad`][dscdocs]; MicrosoftDocs/win32 @ [`ca8274d`][win32].

Local experiments were run on the converting workstation only (Windows 11, PowerShell 5.1.26100
and 7.6.6): compiling configurations to MOF in the scratchpad, and read-only `Test` calls against
`HKCU:\Software`. Nothing was installed system-wide and the lab VM was not touched.

## 1. What the schema declares and what the code switches on

- `RegistryAccessEntry.schema.mof:6` ([link][acd-mof]): `Inheritance` is
  `ValueMap{"Key","KeySubkeys","SubKeys"}, Values{"This Key Only","This Key and Subkeys","SubKeys Only"}`.
  The ValueMap and Values lists are **different strings**. `AccessControlList` (line 23) and
  `AccessControlEntry` (line 16) are `EmbeddedInstance` string arrays.
- `RegistryAccessEntry.psm1:444-482` ([link][acd-flag]) `Get-RegistryRuleInheritenceFlag` switches
  on `"Key"`, `"KeySubkeys"` and `"Subkeys"`, so it matches the **ValueMap** form. PowerShell's
  `switch` ignores case, so `SubKeys` matches as well. Any other string matches no branch,
  `$InheritanceFlag`/`$PropagationFlag` are never assigned, and the function returns `$null` for both.
- `RegistryAccessEntry.psm1:349` ([link][acd-rule]) passes those flags straight to
  `New-Object System.Security.AccessControl.RegistryAccessRule(...)`. With `$null` for the two
  enum arguments, no overload binds: *Cannot find an overload for "RegistryAccessRule" and the
  argument count: "5"*. That is the error seen through win_dsc. `Test-TargetResource` reaches it
  from lines 279/295, and `Set-TargetResource` from lines 136/153.
- If `Inheritance` is left out entirely, `Get-RegistryRuleInheritenceFlag`'s parameter is
  `Mandatory` `[string]` (lines 448-451), so a `$null` fails to bind. Omitting it is no escape.
- `Get-TargetResource` goes the **other** way. It builds `Inheritance` with
  `Get-RegistryRuleInheritenceName` (line 64), which returns the display strings `"This Key Only"`,
  `"This Key and Subkeys"` and `"Subkeys Only"` (lines 499-515). So the resource's own Get output
  cannot be fed back to its Test/Set.
- The unit tests use the ValueMap form throughout. `Tests/TestHelper.psm1:232-235` limits the
  helper's `-Inheritance` to `ValidateSet("Key", "KeySubkeys", "Subkeys")`, and
  `Tests/Unit/RegistryAccessEntry.Tests.ps1` passes `'Key'`, `'KeySubkeys'` (line 253) and
  `'Subkeys'` (line 321). Those tests call the `*-TargetResource` functions directly, with no DSC
  engine in between.
- For contrast, `NTFSAccessEntry.schema.mof:14` declares **identical** ValueMap and Values lists
  (`"This folder only"`, …). `Get-NtfsInheritenceFlag` (`AccessControlResourceHelper.psm1:324-349`)
  switches on those same strings. So the NTFS resource works with either form, and only the
  registry resource has the mismatch.

## 2. How the project's own examples call it

- `Examples/RegistryAccessEntry_example.ps1:1-42` ([link][acd-ex-reg]) is a `Configuration` block
  (`Import-DscResource -Module AccessControlDsc`) that nests the instances as DSC keywords:
  `AccessControlList = @( AccessControlList { Principal = …; ForcePrincipal = $True;
  AccessControlEntry = @( AccessControlEntry { AccessControlType = 'Allow'; Rights = 'FullControl';
  Inheritance = 'This Key and Subkeys'; Ensure = 'Present' } ) } … )`. Line 20 uses
  `'This Key and Subkeys'` and line 34 uses `'This Key Only'`. Both are the **Values** (display)
  form.
- `Examples/NtfsAccessEntry_example.ps1:1-75` ([link][acd-ex-ntfs]) has the same shape with
  `NTFSAccessControlList` / `NTFSAccessControlEntry` and `Inheritance = 'This folder and files'`
  (line 19). For NTFS, Values and ValueMap are the same string.
- `Tests/Integration/RegistryAccessEntry.Config.ps1:27` also writes `'This Key and Subkeys'` inside a
  `Configuration`.
- The README documents the Values form: `README.md:133`, *"{ This Key Only | This Key and Subkeys |
  SubKeys Only }"* ([link][acd-readme]).

So every example and doc is written for the **configuration keyword → MOF** path, using display
strings. No example calls the resource through `Invoke-DscResource`.

## 3. Which form reaches the `.psm1`

### 3a. Compiling a configuration maps Values → ValueMap

- `CimDSCParser.cs:1467-1523` ([link][ps-parse]) reads the schema when it builds the DSC keyword.
  `Values` goes into `keyProp.Values` (line 1473), and `ValueMap` is zipped against it into
  `keyProp.ValueMap.Add(key, value)`, where the key is the Values entry and the value is the
  ValueMap entry (lines 1510-1523).
- The generated keyword function (`CimKeywordImplementationFunctionText`, same file) validates the
  user's value against **Values** (lines 3922-3944, `$allowedValues = …Values`, error
  `UnsupportedValueForProperty`). It then **replaces** it with the ValueMap entry before writing
  the instance: `$canonicalizedValue[$key] = $allowedValueMap[$value[$key]]` (lines 3979-3989).
- `DynamicKeywordProperty.ValueMap` is a `Dictionary` built with `StringComparer.OrdinalIgnoreCase`
  (`tokenizer.cs:453-455`, [link][ps-tok]), so the lookup ignores case.
- Experiment (Windows PowerShell 5.1): compiling `Examples/RegistryAccessEntry_example.ps1` writes
  `Inheritance = "KeySubkeys";` and `Inheritance = "Key";` into `localhost.mof`. The same
  configuration with `Inheritance = 'KeySubkeys'` **fails to compile**: *"At least one of the
  values 'KeySubkeys' is not supported or valid for property 'Inheritance' on class
  'AccessControlEntry'. Please specify only supported values: This Key Only, This Key and Subkeys,
  SubKeys Only."* With `'Subkeys Only'` (the casing PowerStig's data uses, §6) it compiles to
  `Inheritance = "SubKeys";`.

So in a configuration you write the Values string, and the resource receives the ValueMap value.
The WMI definition of the qualifiers agrees that the ValueMap entry is the real value. For a string
property, *"the actual allowable values of the property are the entries in the **ValueMap**
array"*, and *"It is up to the application to take advantage of mappings"* (`value-map.md:54,56`,
[link][win32-vm]). Microsoft's DSC authoring page puts it loosely: *"`Values` restricts the values
that can be assigned to the property to the list of values defined in `ValueMap`"*
(`authoringResourceMOF.md:75-77`, [link][dsc-mof]).

### 3b. `Invoke-DscResource` passes the value through unchanged

- PSDesiredStateConfiguration 2.0.7 (PowerShell 7): for a script resource, `Invoke-DscResource`
  imports the `.psm1` and runs `& $type\$functionName @Property`
  (`PSDesiredStateConfiguration.psm1:4776-4801`, function body 4647-4718). There is no validation
  and no ValueMap lookup.
- Windows PowerShell 5.1: `Invoke-DscResource` is a compiled cmdlet,
  `Microsoft.PowerShell.DesiredStateConfiguration.Commands.InvokeDscResourceMethodCommand` in
  `Microsoft.Windows.DSC.CoreConfProviders.dll`, whose source is not published. Its doc says only
  that it *"invokes a DSC resource directly, without creating a configuration document"*
  (`dsc-1.1/…/Invoke-DscResource.md:28-29`, [link][dsc-idr11]). The mapping in §3a lives in the
  keyword function, which this path never runs. There is upstream evidence that 5.1 does no
  mapping: [ansible/ansible#25754][a25754] (2017) and
  [PowerShell/PSDesiredStateConfiguration#121][psdsc121] (*"Invoke-DscResource parameters type
  conversion"*, still **open**) show `Invoke-DscResource` passing a Values string (`"Dword"`) through
  unconverted where a configuration maps it to its ValueMap (`"4"`). The observation recorded on
  #200 matches: `'This Key and Subkeys'` reached `ConvertTo-RegistryAccessRule` unmapped.
- Experiment (PowerShell 7.6.6 with PSDesiredStateConfiguration 2.0.7, `-Method Test`,
  `Path = 'HKCU:\Software'`, client-only `AccessControlList`/`AccessControlEntry` instances):

  | `Inheritance` | Result |
  |---|---|
  | `KeySubkeys` | `InDesiredState = False` (ran) |
  | `Key` | `InDesiredState = False` (ran) |
  | `Subkeys` / `SubKeys` | `InDesiredState = False` (ran) |
  | `This Key and Subkeys` | *Cannot find an overload for "RegistryAccessRule" and the argument count: "5"* |

## 4. How win_dsc validates and converts the property

- `win_dsc.ps1:86-88` ([link][wd-choices]) builds the Ansible arg spec from the CIM class, and
  `choices` comes from the **Values** qualifier:
  `$option.choices = [System.Collections.Generic.List`1[Object]]$Property.Qualifiers['Values'].Value`.
  The ValueMap qualifier is never read. Searching the file for `ValueMap` finds nothing.
- Nested instances go through the same path. `Add-PropertyOption` recurses with
  `Get-OptionSpec -ClassName $Property.ReferenceClassName` for `Instance`/`InstanceArray` properties
  (lines 128-137), so `AccessControlList[].AccessControlEntry[].Inheritance` also gets Values as its
  choices.
- `Ansible.Basic.cs:1021-1045` ([link][ab-choices]) rejects anything outside `choices`, producing the
  message seen on #200 (*"value of {0} must be one of: … Got no match for: …"*). The comparison is
  `StringComparer.OrdinalIgnoreCase` (line 1038), so case differences are accepted silently
  (lines 1047-1059 are commented out).
- `ConvertTo-DscProperty` / `ConvertTo-CimInstance` (`win_dsc.ps1:167-280`) copy the validated value
  into `New-CimInstance -ClassName $ClassName -Property $properties -ClientOnly` (line 196) without
  changing it. The result is passed to `Invoke-DscResource` (line 294, via `Invoke-DscMethod`,
  lines 490-497). Nothing maps Values to ValueMap.
- History: lines 86-87 are the same in the collection's initial commit `ff2f063` (2020-02-19) as at
  HEAD, and the file has had nine commits, none touching this. A search of ansible.windows and
  ansible/ansible issues and PRs for "ValueMap" finds only ansible/ansible#25754 above. That issue
  was closed on the reasoning that `win_dsc` *"doesn't do anything else that pass parameters thru"*
  to `Invoke-DscResource`. No issue or PR covers win_dsc validating against Values while the resource
  expects ValueMap.
- `win_dsc.py:66` ([link][wd-doc]): *"The DSC engine run's each task as the SYSTEM account"*.
  `win_dsc.ps1:8` is `#Requires -Version 5`, and the module runs under the Windows PowerShell
  connection, so it uses the 5.1 `Invoke-DscResource`.

## 5. PowerStig

- `source/PowerStig.psd1:38-41` ([link][stig-psd1]): `RequiredModules` pins
  `@{ModuleName = 'AccessControlDsc'; ModuleVersion = '1.4.3' }`.
- `source/DSCResources/Resources/windows.AccessControl.ps1:11-58` ([link][stig-ac]) drives
  `RegistryAccessEntry` as a **composite-resource configuration**, not through
  `Invoke-DscResource`. It passes the rule's `Inheritance` through unchanged, falling back to
  `'This Key and Subkeys'` (lines 41-50), i.e. the Values form, which the MOF compile then maps.
- The locally cached processed STIG data
  (`%LOCALAPPDATA%\PowerStig\source\StigData\Processed\*.xml`) carries registry inheritance only as
  `This Key and Subkeys` (218 elements) and `Subkeys Only` (8). Both are Values strings, the
  second a case variant of the schema's `SubKeys Only`, which compiles because of the
  case-insensitive map (§3a).

## 6. SYSTEM and `HKLM:\SECURITY`

- The resource calls `Test-Path -Path $Path` then `Get-Acl -Path $Path` in Test (`.psm1:264,270`),
  and `Get-Acl` … `Set-Acl -Path $Path` in Set (lines 122, 171, 240).
- PowerShell's registry provider opens the key before touching its security descriptor:
  `GetSecurityDescriptor` calls `GetRegkeyForPathWriteIfError(path, false)` and
  `SetSecurityDescriptor` calls `GetRegkeyForPathWriteIfError(path, true)`
  (`RegistrySecurity.cs:61,126`, [link][ps-regsec]). Those end in `OpenSubKey(remainingPath,
  writeAccess)` (`RegistryProvider.cs:3566`). `.NET`'s `OpenSubKey(name, writable)` asks for
  `KEY_READ`, or `KEY_READ | KEY_WRITE` when writable (`RegistryKey.cs:500-506,727-739` in
  dotnet/runtime; the same `GetRegistryKeyAccess` in .NET Framework referencesource
  `registrykey.cs:2106-2116`).
- ADR 0023 records the lab host's DACL for `SECURITY` as `O:BAG:SYD:P(A;CI;KA;;;SY)(A;CI;RCWD;;;BA)`.
  Administrators hold only `READ_CONTROL | WRITE_DAC` there, not `KEY_READ`. So `Get-Acl`/`Set-Acl`
  on that key fail for an elevated administrator, and only SYSTEM gets past the open.
- Does the engine run the resource as SYSTEM? In Windows PowerShell 5.1, yes: *"In Windows
  PowerShell 5.1 resources ran under the System context unless specified with user context using
  the key **PsDscRunAsCredential**. In PowerShell 7.0, Resources run in the user's context"*
  (`dsc-2.0/…/Invoke-DscResource.md:161-164`, [link][dsc-idr20]). win_dsc's own docs say the same
  (§4). Under PowerShell 7 / PSDesiredStateConfiguration 2.x the call is in-process (§3b) and runs
  as the caller.

## Answers

1. **Examples.** Both examples write nested `AccessControlList { … AccessControlEntry { … } }`
   keywords inside a `Configuration` and give `Inheritance` as the **Values** display string
   (`'This Key and Subkeys'`, `'This Key Only'`, `'This folder and files'`). The README lists the
   same strings. The unit tests, which skip DSC, use the **ValueMap** keys.
2. **Which form arrives.** Compiling a configuration validates against Values and writes the
   **ValueMap** value into the MOF, so the `.psm1` sees `KeySubkeys` (CimDSCParser.cs:3979-3989;
   reproduced). `Invoke-DscResource` does no mapping: in 2.0.7 it splats the hashtable straight into
   `*-TargetResource` (shown in source). In 5.1 the source is closed, but #121 and #25754 and the
   #200 observation all show the value passing through unchanged.
3. **win_dsc** takes `choices` from **Values** only (`win_dsc.ps1:86-88`, unchanged since 2020),
   validates case-insensitively (`Ansible.Basic.cs:1038`), and passes the Values string through
   unmapped (`win_dsc.ps1:196`). No issue or PR about this mismatch was found. The closest are
   ansible/ansible#25754 (closed) and PSDesiredStateConfiguration#121 (open).
4. **No `Inheritance` value works through win_dsc.** It accepts only `This Key Only` /
   `This Key and Subkeys` / `SubKeys Only`, in any case. The resource's switch understands only
   `Key` / `KeySubkeys` / `Subkeys`. The two sets don't overlap, and omitting the property fails the
   `Mandatory` binding. `Invoke-DscResource` called with the ValueMap key **does work**:
   `KeySubkeys`, `Key` and `Subkeys` all ran `Test` under PowerShell 7 + PSDSC 2.0.7, and
   `This Key and Subkeys` reproduced the overload error. With 5.1's LCM-backed `Invoke-DscResource`,
   **`KeySubkeys` is untested.** It is expected to work, because that LCM ran the resource with a
   value outside ValueMap, so it is not validating against ValueMap, and a compiled MOF hands it
   `KeySubkeys` anyway.
5. **Dev vs 1.4.3.** The resource code, schema and examples on `Dev` are identical to 1.4.3, so
   no fix exists upstream. The schema's ValueMap/Values have been unchanged since 2017-11. PowerStig
   pins **AccessControlDsc 1.4.3** and drives the resource only through compiled configurations.
6. **SYSTEM.** Yes, it needs SYSTEM. `Get-Acl`/`Set-Acl` open the key for `KEY_READ`(+`KEY_WRITE`)
   first, which `SECURITY`'s DACL grants only to SYSTEM. Under Windows PowerShell 5.1 the DSC engine
   (LCM, and so win_dsc and 5.1 `Invoke-DscResource`) runs resources as SYSTEM. Under PowerShell 7
   `Invoke-DscResource` runs as the caller, so it would hit the same access-denied as `win_acl`
   without `become`.

**Since verified on the lab host** (stig-win11, Windows 11 build 26300, Windows PowerShell 5.1,
AccessControlDsc 1.4.3, `seclogon` disabled, execution policy set to `RemoteSigned` for the test):
5.1 `Invoke-DscResource` with `Inheritance = 'KeySubkeys'` on `HKLM:\SECURITY` returned
`InDesiredState = true` for the SYSTEM FullControl entry, `false` then `true` around a `Set` that
added a new entry, and the DACL showed it. The example's compiled-configuration pattern did the
same, with `Inheritance = "KeySubkeys"` in the MOF. Neither needed `become`.

**Not verified:** the 5.1 cmdlet's internals (closed source); and why `Restricted` execution policy
stopped the LCM loading the resource on Windows 11. That was observed on #200 but not researched
here.

[acd]: https://github.com/mcollera/AccessControlDsc/tree/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579
[acd-mof]: https://github.com/mcollera/AccessControlDsc/blob/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579/DscResources/RegistryAccessEntry/RegistryAccessEntry.schema.mof#L6
[acd-flag]: https://github.com/mcollera/AccessControlDsc/blob/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579/DscResources/RegistryAccessEntry/RegistryAccessEntry.psm1#L444-L482
[acd-rule]: https://github.com/mcollera/AccessControlDsc/blob/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579/DscResources/RegistryAccessEntry/RegistryAccessEntry.psm1#L349
[acd-ex-reg]: https://github.com/mcollera/AccessControlDsc/blob/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579/Examples/RegistryAccessEntry_example.ps1
[acd-ex-ntfs]: https://github.com/mcollera/AccessControlDsc/blob/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579/Examples/NtfsAccessEntry_example.ps1
[acd-readme]: https://github.com/mcollera/AccessControlDsc/blob/1c4d77c8d7fbbf8d57e17163f30138d4fed3c579/README.md#L133
[aw]: https://github.com/ansible-collections/ansible.windows/tree/5814722a681fdb394210be1efe714766f2dc7b5b
[wd-choices]: https://github.com/ansible-collections/ansible.windows/blob/5814722a681fdb394210be1efe714766f2dc7b5b/plugins/modules/win_dsc.ps1#L86-L88
[wd-doc]: https://github.com/ansible-collections/ansible.windows/blob/5814722a681fdb394210be1efe714766f2dc7b5b/plugins/modules/win_dsc.py#L66
[ab]: https://github.com/ansible/ansible/tree/01a2851cbb394475aa9375455fdec3dc279539f8
[ab-choices]: https://github.com/ansible/ansible/blob/01a2851cbb394475aa9375455fdec3dc279539f8/lib/ansible/module_utils/csharp/Ansible.Basic.cs#L1021-L1059
[pwsh]: https://github.com/PowerShell/PowerShell/tree/2150ca16efba746bc0b0793039986bedaeddefec
[ps-parse]: https://github.com/PowerShell/PowerShell/blob/2150ca16efba746bc0b0793039986bedaeddefec/src/System.Management.Automation/DscSupport/CimDSCParser.cs#L1467-L1523
[ps-tok]: https://github.com/PowerShell/PowerShell/blob/2150ca16efba746bc0b0793039986bedaeddefec/src/System.Management.Automation/engine/parser/tokenizer.cs#L453-L455
[ps-regsec]: https://github.com/PowerShell/PowerShell/blob/2150ca16efba746bc0b0793039986bedaeddefec/src/System.Management.Automation/namespaces/RegistrySecurity.cs#L61
[stig]: https://github.com/microsoft/PowerStig/tree/efa8aec879259ade7db396715850c58df9f44e81
[stig-psd1]: https://github.com/microsoft/PowerStig/blob/efa8aec879259ade7db396715850c58df9f44e81/source/PowerStig.psd1#L38-L41
[stig-ac]: https://github.com/microsoft/PowerStig/blob/efa8aec879259ade7db396715850c58df9f44e81/source/DSCResources/Resources/windows.AccessControl.ps1#L11-L58
[dscdocs]: https://github.com/MicrosoftDocs/PowerShell-Docs-DSC/tree/992e0ad719d1400d060655fc9fbff32cc7ab9126
[dsc-mof]: https://github.com/MicrosoftDocs/PowerShell-Docs-DSC/blob/992e0ad719d1400d060655fc9fbff32cc7ab9126/dsc/docs-conceptual/dsc-1.1/resources/authoringResourceMOF.md
[dsc-idr11]: https://github.com/MicrosoftDocs/PowerShell-Docs-DSC/blob/992e0ad719d1400d060655fc9fbff32cc7ab9126/dsc/dsc-1.1/PSDesiredStateConfiguration/Invoke-DscResource.md
[dsc-idr20]: https://github.com/MicrosoftDocs/PowerShell-Docs-DSC/blob/992e0ad719d1400d060655fc9fbff32cc7ab9126/dsc/dsc-2.0/PSDesiredStateConfiguration/Invoke-DscResource.md
[win32]: https://github.com/MicrosoftDocs/win32/tree/ca8274decead49403d70ceeed4af8d4ca74eaf11
[win32-vm]: https://github.com/MicrosoftDocs/win32/blob/ca8274decead49403d70ceeed4af8d4ca74eaf11/desktop-src/WmiSdk/value-map.md
[a25754]: https://github.com/ansible/ansible/issues/25754
[psdsc121]: https://github.com/PowerShell/PSDesiredStateConfiguration/issues/121
