# ServiceRule field survey for issue #100

Research for [#100](https://github.com/camusicjunkie/PowerStigConverter/issues/100) (child of
map #98, blocking #99). Scope: how a `ServiceRule`'s `ServiceName`/`StartupType`/`ServiceState`
fields currently reach the generated Ansible task, and what every real `<ServiceRule>` in the
locally cached upstream PowerStig processed STIG data actually says. No code under `Source/` or
`tests/` was changed to produce this - it is a fact-finding pass only; the fix is a separate
ticket.

## 1. How the fields reach the task today

- `Source\Private\Task\Build-AnsibleServiceTask.ps1:16,26,28-29` - the task interpolates
  `$service.ServiceName` and `$service.StartupType` into the task/detail names, but the assert
  itself is a fixed string: `"$registerName.services.state is started"` (line 28), independent of
  either field. `ServiceState` is never referenced anywhere in the file.
- `Source\Files\OrganizationData.psd1:55-63` - the `Service` entry's `Required` list is
  `@('ServiceName', 'StartupType')` and its `Shape` maps only those same two keys
  (`'ServiceName' = 'ServiceName'`, `'StartupType' = 'StartupType'`). `ServiceState` is not a key
  anywhere in the `Service` block.
- `Source\Private\Resolve-AnsibleOrganizationValue.ps1:106-126` - `$value` is built from
  `$data['Shape']`, walking only the properties that entry declares. Since `Service`'s `Shape`
  omits `ServiceState`, `Resolve-AnsibleOrganizationValue` never reads `$Rule.ServiceState` and
  the resolved `.Value` object passed to the generator (`$service` in
  `Build-AnsibleServiceTask.ps1:8`) has no `ServiceState` property at all - the generator could
  not read it even if it tried.
- A repo-wide search confirms zero hits for `ServiceState` anywhere under `Source\`.

Net effect: `ServiceName` and `StartupType` both reach the task (as literals or, when
`OrganizationValueRequired` is true, as `{{ variable }}` references guarded by an incomplete-value
assert); `ServiceState` is discarded before it ever leaves `Resolve-AnsibleOrganizationValue`.

## 2. What the existing test covers

`tests\Build-AnsibleServiceTask.Tests.ps1`:

- `New-ServiceRule` (lines 9-20) builds a fixture rule with only `Id`, `Severity`, `DuplicateOf`,
  `ServiceName`, `StartupType`, `OrganizationValueRequired` - it has no `ServiceState` property at
  all, so no test exercises that field.
- The assertion-shape tests (lines 46-51) only check that the `that` clause starts with the
  registered variable name (`Should-BeLikeString "$register*"`); none pin the literal text
  `is started`, so nothing in the suite currently locks in the hardcoded word.
- The organization-value tests (lines 70-91) cover `ServiceName`/`StartupType` becoming variables
  and being guarded when unanswered; again `ServiceState` never appears.

## 3. Inventory of every `<ServiceRule>` in the cached upstream data

Surveyed `C:\Users\camus\AppData\Local\PowerStig\source\StigData\Processed\*.xml` (148 files,
every product PowerStig ships: Windows Client/Server, IIS, SQL Server, RHEL/OracleLinux/Ubuntu,
browsers, Office, Adobe, etc.) with a recursive search for `<ServiceRule`. Only Windows Client and
Windows Server STIGs contain any `ServiceRule` elements - 12 files, 20 `<Rule>` instances total,
covering 5 distinct STIG IDs:

| Product/File | Rule ID | ServiceName | StartupType | ServiceState | ServiceName | StartupType | ServiceState |
|---|---|---|---|---|---|---|---|
| WindowsClient-10-3.5.xml | V-220732 | `seclogon` | `Disabled` | `Stopped` | literal | literal | literal |
| WindowsClient-10-3.6.xml | V-220732 | `seclogon` | `Disabled` | `Stopped` | literal | literal | literal |
| WindowsClient-11-2.6.xml | V-253289 | `seclogon` | `Disabled` | `Stopped` | literal | literal | literal |
| WindowsClient-11-2.7.xml | V-253289 | `seclogon` | `Disabled` | `Stopped` | literal | literal | literal |
| WindowsServer-2019-DC-3.7.xml | V-205850 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-DC-3.7.xml | V-214936 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-DC-3.8.xml | V-205850 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-DC-3.8.xml | V-214936 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-MS-3.7.xml | V-205850 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-MS-3.7.xml | V-214936 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-MS-3.8.xml | V-205850 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2019-MS-3.8.xml | V-214936 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-DC-2.7.xml | V-254248 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-DC-2.7.xml | V-254265 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-DC-2.8.xml | V-254248 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-DC-2.8.xml | V-254265 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-MS-2.7.xml | V-254248 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-MS-2.7.xml | V-254265 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-MS-2.8.xml | V-254248 (AV) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |
| WindowsServer-2022-MS-2.8.xml | V-254265 (Firewall) | *(blank)* | *(blank)* | `Running` | org-value | org-value | **literal** |

All twenty rows carry `OrganizationValueRequired`: `False` for the two `seclogon` STIG IDs (V-220732,
V-253289), `True` for the three Windows Server STIG IDs (V-205850, V-214936, V-254248, V-254265 -
same shape repeated per DC/MS product and per STIG version).

Field values and org-value markers, cited from the XML itself:

- **Secondary Logon** (`WindowsClient-10-3.6.xml:5967-5985`, identical shape in the other three
  client files): `<OrganizationValueRequired>False</OrganizationValueRequired>`,
  `<ServiceName>seclogon</ServiceName>`, `<ServiceState>Stopped</ServiceState>`,
  `<StartupType>Disabled</StartupType>` - all three fields are concrete literals, none blank.
- **AntiVirus service** (e.g. `WindowsServer-2019-DC-3.8.xml:6649-6680`,
  `WindowsServer-2022-DC-2.8.xml:6892-6921`): `<OrganizationValueRequired>True</OrganizationValueRequired>`,
  `<ServiceName>` and `<StartupType>` both self-closing/empty elements (PowerStig's blank-org-value
  convention - see the `Service` `OrganizationValueTestString` text, e.g.
  `"ServiceName/StartupType is populated with correct AntiVirus service information"`, itself
  confirming only those two fields are meant to be filled in by the organization), while
  `<ServiceState>Running</ServiceState>` is a concrete literal, not blank, sitting right between
  the two blank fields.
- **Host-based firewall service** (e.g. `WindowsServer-2019-DC-3.8.xml:6681-6699`,
  `WindowsServer-2022-DC-2.8.xml:6924-6944`): identical shape - `ServiceName`/`StartupType` blank,
  `ServiceState` a concrete `Running` literal.

The repo's own `WindowsServer-2022-DC-1.0.xml` fixture (`tests\fixtures\PowerStig\source\StigData\Processed\WindowsServer-2022-DC-1.0.xml:65-75`,
referenced by issue #100 and by #98's map) is not part of the real upstream data (no `1.0`
version exists in the cached `Processed` directory - the closest real releases are `2.7`/`2.8`).
That fixture's `V-403` has `<ServiceName />` and `<StartupType />` both blank and **no
`<ServiceState>` element at all** (not even a blank one) - the fixture never carried a
`ServiceState` value to check the hardcoded assert against, consistent with #100's premise.

## 4. Findings

### Does `ServiceState` ever disagree with what `StartupType` alone implies?

No case of direct contradiction was found (e.g. `StartupType=Manual` paired with an expected
`Running` state, or `StartupType=Automatic` paired with an expected `Stopped` state) - but that is
because in every real rule where both fields carry information, they point the same direction:
Secondary Logon pairs `StartupType=Disabled` with `ServiceState=Stopped` (both "off"). The three
Windows Server STIG IDs never give `StartupType` a concrete value to compare against - it is left
blank precisely because the organization must choose it, so there is no way to check it against
`ServiceState=Running` for consistency; only `ServiceState` is fixed in those rules. What the
data does show clearly is that **`ServiceState` and `StartupType` are decided independently by
PowerStig** - `Service`'s own `OrganizationValueTestString` names only `ServiceName`/`StartupType`
as organization-decided, while `ServiceState` is populated by PowerStig itself (as `Running`) even
in the same `<Rule>` where the other two fields are deliberately left blank. That is a form of
disagreement in kind, if not in value: the STIG author trusts the organization to name the
service and its startup type, but not to say whether it should be running.

### Is "is started" ever correct for a real shipped rule, or was that only true by accident of a blank fixture?

Both, depending on which real rule you pick:

- For the two `seclogon` STIG IDs (4 of the 20 rows, `OrganizationValueRequired=False`,
  fully concrete), "is started" is **wrong** - the rule wants the service disabled and stopped,
  the literal opposite. This is the case #99's survey and #100's issue body already identified.
- For the three Windows Server STIG IDs (16 of the 20 rows, `OrganizationValueRequired=True`),
  `ServiceState=Running` is a concrete literal that the generator discards; "started"/"Running" is
  the *intended* state for these rules, but the generator never reads that literal to confirm it -
  it hardcodes the same string it would emit for Secondary Logon too. So even where "is started"
  happens to match the STIG's intent, it is not validated against `ServiceState`; the value used
  to build the assert would be exactly as wrong today if these AV/Firewall rules instead wanted
  `Stopped`, because the generator never looks at the field either way.
- The repo's own `WindowsServer-2022-DC-1.0` fixture (`V-403`) is the one case where the assert
  was truly never exercised against any concrete value at all, since that fixture has no
  `ServiceState` element to check - consistent with #100's framing that the hardcoded assert was
  never validated by a fixture that gave it a real answer to be right or wrong about.

In short: `ServiceState` is populated for every real shipped `ServiceRule` in the current cached
upstream data (never blank itself, even in the 16 rows where `ServiceName`/`StartupType` are
blank organization values) but is read nowhere in `Source\`, so today's fixed "is started" assert
is demonstrably wrong for one shipped rule (Secondary Logon), and unvalidated-but-coincidentally
right for the other three shipped rule IDs (AntiVirus, Firewall).
