function New-AnsibleIisLoggingTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [string] $StigId
    )

    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { return }

            $navParams = @{ TaskId = $rule.Id; StigName = $StigName }

            $logging = Get-AnsibleOrganizationValue -Rule $rule -StigName $StigName
            $logFlags = $logging.LogFlags
            $logFormat = $logging.LogFormat
            $logPeriod = $logging.LogPeriod
            $logTarget = $logging.LogTargetW3C
            $logCustomFields = $logging.LogCustomFieldEntry

            $customFields = if (-not [string]::IsNullOrEmpty($logCustomFields)) {
                foreach ($entry in $logCustomFields.Entry) {
                    @{
                        'DSC_LogCustomField' = [ordered] @{
                            'LogFieldName' = '{0}-{1}' -f $entry.SourceType, $entry.SourceName
                            'SourceName' = $entry.SourceName
                            'SourceType' = $entry.SourceType
                        }
                    }
                }
            }

            $logPath = New-AnsibleVariable @navParams -Type Organization -TaskName 'logpath'

            $task = [ordered] @{
                'name' = '{0} | {1} | IIS Logging on {2}' -f $rule.Id, $rule.Severity.ToUpper(), $logPath
                'ansible.windows.win_dsc' = [ordered] @{
                    'resource_name' = 'IISLogging'
                    'LogPath' = $logPath
                }
                'when' = New-AnsibleVariable @navParams -Type Conditional
            }

            Write-Verbose "  Task: $($task.name)"

            if (-not [string]::IsNullOrEmpty($logFlags)) { $task.'ansible.windows.win_dsc'.LogFlags = $logFlags -split ',' }
            if (-not [string]::IsNullOrEmpty($logFormat)) { $task.'ansible.windows.win_dsc'.LogFormat = $logFormat }
            if (-not [string]::IsNullOrEmpty($logPeriod)) { $task.'ansible.windows.win_dsc'.LogPeriod = $logPeriod }
            if (-not [string]::IsNullOrEmpty($logTarget)) { $task.'ansible.windows.win_dsc'.LogTargetW3C = $logTarget -split ','}
            if (-not [string]::IsNullOrEmpty($logCustomFields)) { $task.'ansible.windows.win_dsc'.LogCustomFields = $customFields }

            $rule.OrganizationValueRequired = "$true"

            @{
                Rule = $rule
                Task = $task
            }
        }
    }
}
