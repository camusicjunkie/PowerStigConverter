function Build-AnsibleWindowsFeatureTask {
    <#
    .SYNOPSIS
        One windows feature, as win_feature takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    @{
        Task = @(
            @{
                Detail = 'Set {0} to {1}' -f $Rule.Name, $Rule.Ensure
                Body = [ordered] @{
                    'ansible.windows.win_feature' = [ordered] @{
                        'name' = $Rule.Name
                        'state' = $Rule.Ensure
                    }
                }
            }
        )
    }
}
