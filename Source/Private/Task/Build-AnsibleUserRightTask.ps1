function Build-AnsibleUserRightTask {
    <#
    .SYNOPSIS
        One user right, as win_user_right takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    @{
        Task = @(
            @{
                Detail = $Rule.DisplayName
                Body = [ordered] @{
                    'ansible.windows.win_user_right' = [ordered] @{
                        # win_user_right takes the constant, not the display name a human reads.
                        'name' = $Rule.Constant
                        # A rule that forces the list replaces whoever holds the right.
                        'action' = if ($Rule.Force -eq 'True') { 'set' } else { 'add' }
                        'users' = $Resolution.Value
                    }
                }
            }
        )
    }
}
