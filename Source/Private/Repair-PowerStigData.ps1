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

        # Moves a rule PowerStig left manual to the type its .log would have hard-coded, while
        # it is still of the type the correction expects.
        if ($correction.HardCodedRule) {
            $hardCoded = $correction.HardCodedRule
            $rule = $rules[$id]

            if ($null -eq $rule -or $rule.ParentNode.LocalName -cne $hardCoded.From) {
                Write-Warning $stale
            }
            else {
                $target = $Xml.DISASTIG.SelectSingleNode($hardCoded.To)
                if ($null -eq $target) { $target = $Xml.DISASTIG.AppendChild($Xml.CreateElement($hardCoded.To)) }
                [void] $target.AppendChild($rule.ParentNode.RemoveChild($rule))

                foreach ($name in $hardCoded.Field.Keys) {
                    # PowerStig keeps dscresource as an attribute and every other field as an element.
                    $attribute = $rule.Attributes | Where-Object Name -eq $name
                    if ($attribute) { $attribute.Value = $hardCoded.Field[$name]; continue }

                    $node = $rule.SelectSingleNode($name)
                    if ($null -eq $node) { $node = $rule.AppendChild($Xml.CreateElement($name)) }
                    $node.InnerText = $hardCoded.Field[$name]
                }

                # An entry the file already has is the organization's answer, or PowerStig's default.
                if ($hardCoded.OrganizationalSetting -and -not $OrganizationalSetting.ContainsKey($id)) {
                    $node = ([xml] '<OrganizationalSettings />').CreateElement('OrganizationalSetting')
                    $node.SetAttribute('id', $id)
                    foreach ($attribute in $hardCoded.OrganizationalSetting.Keys) {
                        $node.SetAttribute($attribute, $hardCoded.OrganizationalSetting[$attribute])
                    }
                    $OrganizationalSetting[$id] = $node
                }
            }
        }

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

        # Field swaps a whole child element; ReplaceInRawString a substring the check text holds exactly once.
        $fieldChanges = if ($correction.Field) { $correction.Field } else { @{} }
        $textEdits = @(
            foreach ($name in $fieldChanges.Keys) { @{ Name = $name; Change = $fieldChanges[$name]; Whole = $true } }
            foreach ($change in @($correction.ReplaceInRawString | Where-Object { $_ })) { @{ Name = 'RawString'; Change = $change; Whole = $false } }
        )
        foreach ($edit in $textEdits) {
            $from = $edit.Change.From
            $node = if ($rules.ContainsKey($id)) { $rules[$id].SelectSingleNode($edit.Name) }
            $text = if ($null -ne $node) { $node.InnerText }

            # String.Replace is ordinal, so the length lost to removing From counts its occurrences.
            $count = if ($null -eq $text) { 0 }
                elseif ($edit.Whole) { [int] ($text -ceq $from) }
                elseif ($from) { ($text.Length - $text.Replace($from, '').Length) / $from.Length }
                else { 0 }

            if ($count -ne 1) {
                Write-Warning $stale
                continue
            }
            $node.InnerText = if ($edit.Whole) { $edit.Change.To } else { $text.Replace($from, $edit.Change.To) }
        }

        $settingChanges = if ($correction.OrganizationalSetting) { $correction.OrganizationalSetting } else { @{} }
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
