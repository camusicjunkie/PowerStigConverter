function New-AnsibleServiceTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{}
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $navParams = @{ TaskId = $rule.Id; StigName = $StigName }

            $resolution = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType 'Service' -StigName $StigName -OrganizationalSetting $OrganizationalSetting
            $service = $resolution.Value
            $serviceName = $service.ServiceName
            $startupType = $service.StartupType

            # The service name is an organization value, so it is a variable reference rather
            # than a name by the time it gets here. The register has to be named at generation
            # time and has to be legal as an ansible variable, so it is named for the rule.
            $registerName = '{0}_{1}_service_info' -f (Get-AnsibleVariablePrefix -StigName $StigName), ($rule.Id -replace 'V-' -replace '[^A-Za-z0-9]+', '_')

            $task = [ordered] @{
                'name' = '{0} | {1} | Assert {2} service is set to {3}' -f $rule.Id, $rule.Severity.ToUpper(), $serviceName, $startupType
                'block' = [ordered] @{
                    'name' = 'Gather info for {0}' -f $serviceName
                    'ansible.windows.win_service_info' = [ordered] @{
                        'name' = $serviceName
                    }
                    'register' = $registerName
                },
                [ordered] @{
                    'name' = 'Assert {0} is set to {1}' -f $serviceName, $startupType
                    'ansible.builtin.assert' = [ordered] @{
                        'that' = "$registerName.services.state is started"
                        'fail_msg' = "$serviceName is not started"
                    }
                }
                'when' = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            @{
                Rule = $rule
                Name = '{0} {1}' -f $serviceName, $startupType
                Task = Add-AnsibleOrganizationValueAssert -Task $task -Resolution $resolution
            }
        }
    }
}
