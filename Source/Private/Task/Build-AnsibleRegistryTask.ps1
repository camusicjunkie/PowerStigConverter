function Build-AnsibleRegistryTask {
    <#
    .SYNOPSIS
        One registry value, as win_regedit takes it.
    #>
    param ($Rule, $StigProfile, $Resolution)

    # Ensure alone decides whether the value is written or removed. The value fields cannot be
    # trusted to say it: PowerStig spells 'no value' as ValueType None on one product and as an
    # empty ValueType on another, so inferring removal from them would encode each product's
    # spelling. See docs/adr/0014.
    $absent = $Rule.Ensure -eq 'Absent'

    # Google-Chrome-2.11 spells six keys ending in a stray `\"` (V-275780 and its siblings), which
    # would put the policy in a subkey literally named "; the policy belongs on the key before it.
    $key = $Rule.Key -replace '\\"$', ''

    # PowerStig always writes registry keys backslash-delimited, regardless of the converting
    # machine's platform, so the leaf is taken by matching that literal character rather than
    # through Split-Path - whose separator comes from the current provider/platform and would
    # leave the key unsplit on a machine where '\' is not a path separator.
    $keyLeaf = $key.Substring($key.LastIndexOf('\') + 1)

    # win_regedit takes only a PowerShell drive path. PowerStig spells the hive in full, abbreviated
    # and in mixed case; the lookup is case-insensitive, and an unrecognised hive passes through.
    $hive, $subKey = $key -split '\\', 2
    $drive = @{ HKEY_LOCAL_MACHINE = 'HKLM'; HKLM = 'HKLM'; HKEY_CURRENT_USER = 'HKCU'; HKCU = 'HKCU' }[$hive.TrimEnd(':')]
    $path = if ($drive) { '{0}:\{1}' -f $drive, $subKey } else { $key }

    $regedit = [ordered] @{
        'path' = $path
        'name' = $Rule.ValueName
    }

    if ($absent) {
        # data and type are meaningless to win_regedit under state absent; name is what keeps it
        # deleting the value rather than the whole key.
        $regedit['state'] = 'absent'
    }
    else {
        $valueData = $Resolution.Value
        # win_regedit wants a number where the value is one; yaml would otherwise read it as text.
        $regedit['data'] = if ([int32]::TryParse($valueData, [ref] $null)) { [int] $valueData } else { $valueData }
        $regedit['type'] = $Rule.ValueType.ToLower()
    }

    @{
        # Block detail, offered in preference order: the key leaf, which 117 of upstream's 133
        # registry sub-rule groups share, then the ValueName, which names the requirement where
        # the halves write one value into two differently-spelled locations. A lone rule has
        # nothing to agree with, so it is named for its value outright. See docs/adr/0015.
        GroupDetail = if (Test-PowerStigSubRuleId -Id $Rule.Id) { @($keyLeaf, $Rule.ValueName) } else { $Rule.ValueName }
        Task = @(
            @{
                # A value name alone can be a bare GUID or '2', so the key it sits in is named too.
                Detail = if ($absent) { 'Remove {1} from {0}' -f $keyLeaf, $Rule.ValueName }
                    else { 'Set {1} in {0}' -f $keyLeaf, $Rule.ValueName }
                Body = [ordered] @{
                    'ansible.windows.win_regedit' = $regedit
                }
            }
        )
    }
}
