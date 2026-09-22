function Build-AnsibleServiceTask {
    <#
    .SYNOPSIS
        Gather a service's state and assert on it - one unit, so one task carrying its own block.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $service = $Resolution.Value

    # Named for the rule, because the service name may be a variable reference by now.
    $registerName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigName $StigName -Suffix 'service_info'

    # ServiceState is the STIG's own fixed answer, never left for the organization to decide -
    # unlike ServiceName/StartupType it carries no Required entry in OrganizationData.psd1, so it
    # is read straight off the rule rather than through $Resolution. win_service_info reports
    # 'started', not PowerStig's 'Running'. See #100.
    $state = switch ($Rule.ServiceState) {
        'Running' { 'started' }
        'Stopped' { 'stopped' }
        default { throw "$($Rule.Id): unrecognized ServiceState '$($Rule.ServiceState)'" }
    }

    @{
        Task = @(
            @{
                Detail = 'Assert {0} service is set to {1}' -f $service.ServiceName, $service.StartupType
                Body = [ordered] @{
                    'block' = [ordered] @{
                        'name' = 'Gather info for {0}' -f $service.ServiceName
                        'ansible.windows.win_service_info' = [ordered] @{
                            'name' = $service.ServiceName
                        }
                        'register' = $registerName
                    },
                    [ordered] @{
                        'name' = 'Assert {0} is set to {1}' -f $service.ServiceName, $service.StartupType
                        'ansible.builtin.assert' = [ordered] @{
                            'that' = "$registerName.services.state is $state"
                            'fail_msg' = "$($service.ServiceName) is not $state"
                        }
                    }
                }
            }
        )
    }
}
