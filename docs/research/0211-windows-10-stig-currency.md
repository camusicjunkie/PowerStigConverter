# Is the Windows 10 STIG still current? (issue #211)

Research for [#211](https://github.com/camusicjunkie/PowerStigConverter/issues/211), a child of the
map [#204](https://github.com/camusicjunkie/PowerStigConverter/issues/204). Scope: whether DISA still
publishes and maintains the Microsoft Windows 10 STIG, its last release, and the latest
`WindowsClient-10` revision PowerStig ships. Read on 2026-10-22. No code was changed.

## Answer

**No. DISA sunset the Windows 10 STIG with its final release, V3R6 (benchmark date 05 Jan 2026),
and dropped it from the quarterly SRG/STIG library that same day.** It has not appeared in any 2026
quarterly library since. PowerStig followed in 4.29.0 (2026-02-25), relabelling it
"Sunset-Microsoft Windows 10 STIG - Ver 3, Rel 6" and calling that its last update for sunset
STIGs. `WindowsClient-10-3.6` is therefore the final revision there will ever be.

Sunset is not the same as removed: V3R6 is still downloadable from DISA, and PowerStig still ships
it (`WindowsClient-10-3.5.xml` and `-3.6.xml`). But by the repo's rule — exclude a product when DISA
has marked its STIG Sunset — `WindowsClient-10` falls out of #204's scope for conversion fixes.

## Timeline

| Date | Event | Source |
| --- | --- | --- |
| 2025-07 | July 2025 library carries `U_MS_Windows_10_V3R4_STIG.zip` | [1] |
| 2025-10-01 | October 2025 library carries `U_MS_Windows_10_V3R5_STIG.zip` | [1], [3] |
| 2025-10-14 | Microsoft ends Windows 10 support (22H2 retirement listed as 10/15/2025 06:59 PT) | [5] |
| 2026-01-05 | V3R6 released: WN10-00-000040 "Updated requirement to move to sunset" | [2], [3], [4] |
| 2026-01-05 | Library revision history, row 01/05/2026, *Deleted content that has been sunset*: `U_MS_Windows_10_V3R6_STIG.zip` | [3] |
| 2026-01 → 2026-10 | No Windows 10 STIG in the January, April, July or October 2026 libraries | [1] |
| 2026-02-25 | PowerStig 4.29.0: "Sunset-Microsoft Windows 10 STIG - Ver 3, Rel 6"; "this will be the last update for Sunset Stigs" | [6] |
| 2026-06-19 | PowerStig 4.30.0 adds Windows 11 V2R7, nothing for Windows 10 | [6] |

## Findings

### 1. DISA's own library records the sunset

DISA's quarterly compilations (`U_SRG-STIG_Library_<Month>_<Year>.zip` on `dl.dod.cyber.mil`) list
their member archives. Windows client entries, read from each archive's central directory [1]:

| Library | Windows 10 | Windows 11 |
| --- | --- | --- |
| July 2025 | `U_MS_Windows_10_V3R4_STIG.zip` | `U_MS_Windows_11_V2R4_STIG.zip` |
| October 2025 | `U_MS_Windows_10_V3R5_STIG.zip` | `U_MS_Windows_11_V2R5_STIG.zip` |
| January 2026 | — | `U_MS_Windows_11_V2R6_STIG.zip` |
| April 2026 | — | `U_MS_Windows_11_V2R7_STIG.zip` |
| July 2026 | — | `U_MS_Windows_11_V2R8_STIG.zip` |
| October 2026 (last-modified 2026-10-07) | — | `U_MS_Windows_11_V2R11_STIG.zip` |

The January 2026 library ships `_SRG-STIG Library Revision History.pdf` (dated 05 January 2026).
Its first row, revision date **01/05/2026**, has the change *"Deleted content that has been
sunset"*, and the Deleted list names **`U_MS_Windows_10_V3R6_STIG.zip`** alongside IE11, the Office
2016 suite and others [3]. That is DISA stating, in a first-party document, that V3R6 is sunset
content.

### 2. V3R6 is a closing release

- The V3R6 XCCDF (`U_MS_Windows_10_STIG_V3R6_Manual-xccdf.xml`) carries
  `<status date="2025-11-24">accepted</status>` and `Release: 6 Benchmark Date: 05 Jan 2026`, 267
  groups [2].
- Its revision history PDF and the January 2026 maintenance release notes both list, for "Microsoft
  Windows 10 STIG, Version 3, Release 6": *WN10-00-000040 — Updated requirement to move to sunset*
  [2], [4]. That rule (CAT I) now reads: check `winver.exe`; *"If the 'About Windows' dialog box does
  not display a version supported by the vendor, this is a finding."* Fix: *"Upgrade to a supported
  version of the operating system."* [2]. The SCAP benchmark V3R6 updated its OVAL for the same rule
  "to verify the version is supported by the vendor" [4].
- The sunset is DISA's, not just a per-rule edit: the same release is the one the library revision
  history deletes as sunset content [3]. Search-engine summaries that read "WN10-00-000040 moved to
  sunset" as the *only* sunset signal miss that row.

### 3. Still published, but as sunset

`https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_10_V3R6_STIG.zip` still returns
200 (Last-Modified 2026-04-28). V3R5 does too; there is no V3R7 (404) [1]. DISA's sunset page defines
sunset products as ones "no longer supported by DISA" — still usable, but not maintained [7].

### 4. What PowerStig ships

- `source/StigData/Processed` on `dev` @ `efa8aec` holds `WindowsClient-10-3.5.xml`,
  `WindowsClient-10-3.6.xml` (plus `.org.default.xml` each) [6].
- `WindowsClient-10-3.6.xml` header: `filename="U_MS_Windows_10_STIG_V3R6_Manual-xccdf.xml"
  releaseinfo="Release: 6 Benchmark Date: 05 Jan 2026"`. Its only commit is `6a4ee5c`
  (2026-02-18) "Update Sunsetted and Remove Retired STIGS" [6].
- 4.29.0's notes say retired STIGs were removed and this was "the last update for Sunset Stigs";
  Windows 10 is in the Sunset list, not the Removed list [6]. Expect PowerStig to drop it on a
  future retirement pass, with no further revisions before then.

### Aside: PowerStig lags DISA on Windows 11

DISA's October 2026 library carries Windows 11 **V2R11**; PowerStig's newest is `WindowsClient-11-2.7`
(April 2026's). Not part of #211's question, but #204's Windows 11 work runs against a revision three
quarters behind DISA.

## Implication for #204

The map says `WindowsClient-10` "gets the same conversion fixes … if its STIG is still current". It
is not: DISA sunset it on 2026-01-05. The project memory note recording Windows 10 as
"still current" (2026-10-21) predates this check and is wrong on that point.

Choosing what to do with the existing `WindowsClient-10` fixtures and coverage rows is #204's
decision, not this ticket's.

## How to check this again

cyber.mil and ncp.nist.gov are JavaScript-rendered and return an empty shell to fetchers. The
download host is not: the quarterly library zips at
`https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_SRG-STIG_Library_<Month>_<Year>.zip`
answer HEAD and ranged GETs, so their member list can be read without downloading ~370 MB, and the
`_SRG-STIG Library Revision History.pdf` inside each one names the sunset deletions per quarter.

## Sources

1. DISA quarterly SRG/STIG libraries, `dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_SRG-STIG_Library_{July_2025,October_2025,January_2026,April_2026,July_2026,October_2026}.zip` — member listings via HTTP range requests; plus HEAD on `U_MS_Windows_10_V3R{5,6,7}_STIG.zip`.
2. `U_MS_Windows_10_V3R6_STIG.zip` from DISA: `U_MS_Windows_10_STIG_V3R6_Manual-xccdf.xml` and `U_MS_Windows_10_V3R6_Revision_History.pdf` (05 January 2026).
3. `_SRG-STIG Library Revision History.pdf` (05 January 2026), inside `U_SRG-STIG_Library_January_2026.zip`, page 1, row 01/05/2026.
4. `_January_2026_Maintenance_Release.pdf` ("January 2026 Maintenance Release: STIGs to be released", Release Date January 5, 2026), inside the same library.
5. Microsoft Lifecycle, [Windows 10 Enterprise and Education](https://learn.microsoft.com/en-us/lifecycle/products/windows-10-enterprise-and-education): end of support October 14, 2025; 22H2 is the final version; LTSC releases continue on their own lifecycles.
6. [microsoft/PowerStig](https://github.com/microsoft/PowerStig): [`source/StigData/Processed`](https://github.com/microsoft/PowerStig/tree/dev/source/StigData/Processed) on `dev` @ `efa8aec`; [releases 4.28.0–4.30.0](https://github.com/microsoft/PowerStig/releases); commit `6a4ee5c`.
7. DISA, [Sunset Products](https://www.cyber.mil/stigs/sunset-products/) — page is JS-rendered; definition quoted via search-engine extract, not a direct fetch.
