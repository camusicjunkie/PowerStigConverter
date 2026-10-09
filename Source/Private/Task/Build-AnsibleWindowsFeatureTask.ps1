function Build-AnsibleWindowsFeatureTask {
    <#
    .SYNOPSIS
        One windows feature, as win_feature takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # win_feature is a native module, so it is handed Ansible's own lowercase state words rather
    # than PowerStig's Present/Absent. A rule with no Ensure takes the present path. See ADR 0014.
    $state = if ($Rule.Ensure -eq 'Absent') { 'absent' } else { 'present' }

    $body = [ordered] @{
        'ansible.windows.win_feature' = [ordered] @{
            'name' = $Rule.Name
            'state' = $state
        }
    }

    # A feature the target OS does not ship is already absent, but win_feature fails on the name.
    # The generator cannot know what the target ships (ADR 0005), so the task tolerates exactly
    # that error. See #146.
    if ($state -eq 'absent') {
        $registerName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigName $StigName -Suffix 'feature_result'
        $body['register'] = $registerName
        $body['failed_when'] = "$registerName is failed and 'is not valid' not in ($registerName.msg | default(''))"
    }

    @{
        Task = @(
            @{
                Detail = 'Set {0} to {1}' -f $Rule.Name, $state
                Body = $body
            }
        )
    }
}
