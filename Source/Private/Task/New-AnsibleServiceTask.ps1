function New-AnsibleServiceTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { return }

            $navParams = @{ TaskId = $rule.Id; TaskName = $name; StigName = $StigName }

            $service = Get-AnsibleOrganizationValue -Rule $rule -StigName $StigName
            $serviceName = $service.ServiceName
            $startupType = $service.StartupType

            $name = '{0} {1}' -f $serviceName, $startupType
            $rule.OrganizationValueRequired = "$false"

            $task = [ordered] @{
                'name' = '{0} | {1} | Assert {2} service is set to {3}' -f $rule.Id, $rule.Severity.ToUpper(), $serviceName, $startupType
                'block' = [ordered] @{
                    'name' = 'Gather info for {0}' -f $serviceName
                    'ansible.windows.win_service_info' = [ordered] @{
                        'name' = $serviceName
                    }
                    'register' = 'server_2022_stig_{0}_service_info' -f $serviceName
                },
                [ordered] @{
                    'name' = 'Assert {0} is set to {1}' -f $serviceName, $startupType
                    'ansible.builtin.assert' = [ordered] @{
                        'that' = "$('server_2022_stig_{0}_service_info.services.state' -f $serviceName) is started"
                        'fail_msg' = "$serviceName is not started"
                    }
                }
                'when' = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            @{
                Rule = $rule
                Name = $name
                Task = $task
            }
        }
    }
}
