function Build-AnsibleServiceTask {
    <#
    .SYNOPSIS
        Sets a service's startup type and state with win_service, after checking it is installed.
        See docs/adr/0022.
    #>
    param ($Rule, $StigProfile, $Resolution)

    $service = $Resolution.Value

    # Named for the rule, because the service name may be a variable reference by now.
    $registerName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigProfile $StigProfile -Suffix 'service_info'

    # ServiceState is the STIG's own fixed answer, never left for the organization to decide -
    # unlike ServiceName/StartupType it carries no Required entry in OrganizationData.psd1, so it
    # is read straight off the rule rather than through $Resolution. See #100.
    $state = switch ($Rule.ServiceState) {
        'Running' { 'started' }
        'Stopped' { 'stopped' }
        default { throw "$($Rule.Id): unrecognized ServiceState '$($Rule.ServiceState)'" }
    }

    # PowerStig writes the DSC Service resource's startup types; win_service has its own words.
    $startMode = @{ 'Automatic' = 'auto'; 'Manual' = 'manual'; 'Disabled' = 'disabled' }

    # An organization variable holds PowerStig's word, so it is mapped when the play runs. An
    # Ansible word passes through, so -e can give either.
    $startupVariable = @($Resolution.Variable | Where-Object { $_.Part -eq 'StartupType' })[0]
    $startModeValue = if ($startupVariable) {
        $pairs = ($startMode.Keys | Sort-Object | ForEach-Object { "'{0}': '{1}'" -f $_, $startMode[$_] }) -join ', '
        '{{{{ {{{0}}}.get({1}, {1}) }}}}' -f $pairs, $startupVariable.Name
    }
    elseif ($startMode.ContainsKey([string] $service.StartupType)) { $startMode[[string] $service.StartupType] }
    else { throw "$($Rule.Id): unrecognized StartupType '$($service.StartupType)'" }

    $installed = "$registerName.services | length == 1"
    $detail = 'Set {0} service to {1} and {2}' -f $service.ServiceName, $service.StartupType, $state

    $set = [ordered] @{
        'name' = 'Set {0} to {1} and {2}' -f $service.ServiceName, $service.StartupType, $state
        'ansible.windows.win_service' = [ordered] @{
            'name' = $service.ServiceName
            'start_mode' = $startModeValue
            'state' = $state
        }
    }

    # A service the target lacks cannot run, so a rule wanting it running fails on it; one
    # wanting it stopped is already met, and win_service would fail on the missing name.
    $members = @(
        [ordered] @{
            'name' = 'Gather info for {0}' -f $service.ServiceName
            'ansible.windows.win_service_info' = [ordered] @{
                'name' = $service.ServiceName
            }
            'register' = $registerName
        }
        if ($state -eq 'started') {
            [ordered] @{
                'name' = 'Assert {0} is installed' -f $service.ServiceName
                'ansible.builtin.assert' = [ordered] @{
                    'that' = $installed
                    'fail_msg' = "$($service.ServiceName) is not installed, so it cannot be set to run"
                }
            }
        }
        else {
            $set['when'] = $installed
        }
        $set
    )

    @{
        Task = @(
            @{
                Detail = $detail
                Body = [ordered] @{ 'block' = $members }
            }
        )
    }
}
