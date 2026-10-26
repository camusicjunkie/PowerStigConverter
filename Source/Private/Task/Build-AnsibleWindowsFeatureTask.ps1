function Build-AnsibleWindowsFeatureTask {
    <#
    .SYNOPSIS
        One windows feature, as win_feature takes it on Server and win_optional_feature on a client.
    #>
    param ($Rule, $StigProfile, $Resolution)

    # win_feature is a native module, so it is handed Ansible's own lowercase state words rather
    # than PowerStig's Present/Absent. A rule with no Ensure takes the present path. See ADR 0014.
    $state = if ($Rule.Ensure -eq 'Absent') { 'absent' } else { 'present' }

    # Chosen by product, not PowerStig's dscresource, which says WindowsFeature for Windows 11.
    # A client has no Server Manager cmdlets, so its features are optional features. See #194.
    if ($StigProfile.Target -eq 'Client') {
        $module = 'ansible.windows.win_optional_feature'
        $missingMessage = 'Failed to find feature'
    }
    else {
        $module = 'ansible.windows.win_feature'
        $missingMessage = 'is not valid'
    }

    $body = [ordered] @{
        $module = [ordered] @{
            'name' = $Rule.Name
            'state' = $state
        }
    }

    # A feature the target OS does not ship is already absent, but either module fails on the name.
    # The generator cannot know what the target ships (ADR 0005), so the task tolerates exactly
    # that error. See #146.
    if ($state -eq 'absent') {
        $registerName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigProfile $StigProfile -Suffix 'feature_result'
        $body['register'] = $registerName
        $body['failed_when'] = "$registerName is failed and '$missingMessage' not in ($registerName.msg | default(''))"
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
