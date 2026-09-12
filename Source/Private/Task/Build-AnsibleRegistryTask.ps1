function Build-AnsibleRegistryTask {
    <#
    .SYNOPSIS
        One registry value, as win_regedit takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $valueData = $Resolution.Value
    # win_regedit wants a number where the value is one; yaml would otherwise read it as text.
    $parsedValueData = if ([int32]::TryParse($valueData, [ref] $null)) { [int] $valueData } else { $valueData }

    # PowerStig always writes registry keys backslash-delimited, regardless of the converting
    # machine's platform, so the leaf is taken by matching that literal character rather than
    # through Split-Path - whose separator comes from the current provider/platform and would
    # leave the key unsplit on a machine where '\' is not a path separator.
    $keyLeaf = $Rule.Key.Substring($Rule.Key.LastIndexOf('\') + 1)

    @{
        # Sub-rules of one requirement share a key, so the block is named for it.
        GroupDetail = if (Test-PowerStigSubRuleId -Id $Rule.Id) { $keyLeaf } else { $Rule.ValueName }
        Task = @(
            @{
                Detail = 'Set {0}' -f $Rule.ValueName
                Body = [ordered] @{
                    'ansible.windows.win_regedit' = [ordered] @{
                        'path' = $Rule.Key
                        'name' = $Rule.ValueName
                        'data' = $parsedValueData
                        'type' = $Rule.ValueType.ToLower()
                    }
                }
            }
        )
    }
}
