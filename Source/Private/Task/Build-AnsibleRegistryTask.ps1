function Build-AnsibleRegistryTask {
    <#
    .SYNOPSIS
        One registry value, as win_regedit takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $valueData = $Resolution.Value
    # win_regedit wants a number where the value is one; yaml would otherwise read it as text.
    $parsedValueData = if ([int32]::TryParse($valueData, [ref] $null)) { [int] $valueData } else { $valueData }

    @{
        # Sub-rules of one requirement share a key, so the block is named for it.
        GroupDetail = if ($Rule.Id -match '\.[a-z]$') { Split-Path -Path $Rule.Key -Leaf } else { $Rule.ValueName }
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
