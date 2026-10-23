function Repair-PowerStigData {
    <#
    .SYNOPSIS
        Applies RuleCorrection.psd1 to one processed STIG and its org settings, in place.
    .DESCRIPTION
        Corrects data PowerStig got wrong, rule by rule, before any generator sees it, so a
        generator never has to guess at bad input. Both arguments are this conversion's own
        freshly loaded copies. A correction that finds nothing to change is warned about rather
        than skipped silently, since the data has moved on and the entry should go. See
        docs/adr/0020.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [xml] $Xml,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable] $OrganizationalSetting,

        # The processed file's base name, revision included: WindowsServer-2025-MS-1.1.
        [Parameter(Mandatory)]
        [string] $StigFile
    )

    $corrections = $script:ruleCorrection[$StigFile]
    if (-not $corrections) { return }

    $rules = @{}
    foreach ($ruleType in ($Xml.DISASTIG.psobject.Properties.Name -like '*Rule')) {
        foreach ($rule in $Xml.DISASTIG.$ruleType.Rule) { $rules[$rule.id] = $rule }
    }

    foreach ($id in $corrections.Keys) {
        $correction = $corrections[$id]
        $stale = '{0} {1}: the correction in RuleCorrection.psd1 no longer matches the data. Check it and update or remove it.' -f $StigFile, $id

        if ($correction.RemoveEntry) {
            $match = $correction.RemoveEntry
            $entries = @(if ($rules.ContainsKey($id)) {
                $rules[$id].AccessControlEntry.Entry | Where-Object {
                    $entry = $_
                    $entry -and -not ($match.Keys | Where-Object { $entry.$_ -cne $match[$_] })
                }
            })

            if ($entries.Count -eq 0) { Write-Warning $stale }
            foreach ($entry in $entries) { [void] $entry.ParentNode.RemoveChild($entry) }
        }

        # Ordinal, case-sensitive substring replacement within the rule's check text.
        foreach ($change in @($correction.RawString | Where-Object { $_ })) {
            $node = if ($rules.ContainsKey($id)) { $rules[$id].SelectSingleNode('RawString') }

            if ($null -eq $node -or -not $node.InnerText.Contains($change.From)) {
                Write-Warning $stale
                continue
            }
            $node.InnerText = $node.InnerText.Replace($change.From, $change.To)
        }

        $settingChanges =if ($correction.OrganizationalSetting) { $correction.OrganizationalSetting } else { @{} }
        foreach ($attribute in $settingChanges.Keys) {
            $change = $settingChanges[$attribute]
            $node = $OrganizationalSetting[$id]

            if ($null -eq $node -or $node.GetAttribute($attribute) -cne $change.From) {
                Write-Warning $stale
                continue
            }
            $node.SetAttribute($attribute, $change.To)
        }
    }
}
