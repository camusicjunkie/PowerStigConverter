function Build-AnsibleNxServiceTask {
    <#
    .SYNOPSIS
        One systemd unit, asserted directly - every in-scope product is systemd-era. See ADR 0008.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $enabled = $Rule.Enabled -eq 'True'
    $enabledWord = if ($enabled) { 'enabled' } else { 'disabled' }

    $detail = 'Ensure {0} service is {1}' -f $Rule.Name, $enabledWord
    if ($Rule.State) { $detail += ' and {0}' -f $Rule.State }

    $systemd = [ordered] @{
        'name' = $Rule.Name
        'enabled' = $enabled
    }

    # Both in-scope rules leave this blank, so omitting it beats defaulting to a state PowerStig
    # never asked for.
    if ($Rule.State) { $systemd.state = $Rule.State }

    @{
        Task = @(
            @{
                Detail = $detail
                Body = [ordered] @{
                    'ansible.builtin.systemd_service' = $systemd
                    'become' = $true
                }
            }
        )
    }
}
