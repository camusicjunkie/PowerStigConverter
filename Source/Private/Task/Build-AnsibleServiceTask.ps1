function Build-AnsibleServiceTask {
    <#
    .SYNOPSIS
        Gather a service's state and assert on it - one unit, so one task carrying its own block.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $service = $Resolution.Value

    # Named for the rule, because the service name may be a variable reference by now.
    $registerName = '{0}_{1}_service_info' -f (Get-AnsibleVariablePrefix -StigName $StigName), ($Rule.Id -replace 'V-' -replace '[^A-Za-z0-9]+', '_')

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
                            'that' = "$registerName.services.state is started"
                            'fail_msg' = "$($service.ServiceName) is not started"
                        }
                    }
                }
            }
        )
    }
}
