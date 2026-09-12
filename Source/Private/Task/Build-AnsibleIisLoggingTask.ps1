function Build-AnsibleIisLoggingTask {
    <#
    .SYNOPSIS
        IIS logging, through win_dsc - there is no ansible module covering it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $logging = $Resolution.Value

    # No org settings attribute feeds the log path, so it is a role variable the site fills in
    # rather than an organization value. See docs/adr/0004.
    $logPath = Get-AnsibleVariableReference -TaskId $Rule.Id -TaskName 'logpath' -StigName $StigName

    $dsc = [ordered] @{
        'resource_name' = 'IISLogging'
        'LogPath' = $logPath
    }

    # A setting the rule has nothing for is left out rather than sent empty.
    if ($logging.LogFlags) { $dsc.LogFlags = $logging.LogFlags }
    if (-not [string]::IsNullOrEmpty($logging.LogFormat)) { $dsc.LogFormat = $logging.LogFormat }
    if (-not [string]::IsNullOrEmpty($logging.LogPeriod)) { $dsc.LogPeriod = $logging.LogPeriod }
    if ($logging.LogTarget) { $dsc.LogTargetW3C = $logging.LogTarget }

    if (-not [string]::IsNullOrEmpty($logging.LogCustomFields)) {
        $dsc.LogCustomFields = @(
            foreach ($entry in $logging.LogCustomFields.Entry) {
                @{
                    'DSC_LogCustomField' = [ordered] @{
                        'LogFieldName' = '{0}-{1}' -f $entry.SourceType, $entry.SourceName
                        'SourceName' = $entry.SourceName
                        'SourceType' = $entry.SourceType
                    }
                }
            }
        )
    }

    @{
        Task = @(
            @{
                Detail = 'IIS Logging on {0}' -f $logPath
                Body = [ordered] @{ 'ansible.windows.win_dsc' = $dsc }
            }
        )
    }
}
