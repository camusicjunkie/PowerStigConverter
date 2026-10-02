function Build-AnsibleWindowsFeatureTask {
    <#
    .SYNOPSIS
        One windows feature, as win_feature takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # win_feature is a native module, so it is handed Ansible's own lowercase state words rather
    # than PowerStig's Present/Absent. A rule with no Ensure takes the present path. See ADR 0014.
    $state = if ($Rule.Ensure -eq 'Absent') { 'absent' } else { 'present' }

    @{
        Task = @(
            @{
                Detail = 'Set {0} to {1}' -f $Rule.Name, $state
                Body = [ordered] @{
                    'ansible.windows.win_feature' = [ordered] @{
                        'name' = $Rule.Name
                        'state' = $state
                    }
                }
            }
        )
    }
}
