function Build-AnsibleWebConfigurationPropertyTask {
    <#
    .SYNOPSIS
        One IIS web configuration property, through win_dsc.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $parsedConfigSection = if (Test-PowerStigSubRuleId -Id $Rule.Id) { Split-Path -Path $Rule.ConfigSection } else { $Rule.ConfigSection }

    # A system.web section lives under the web root, everything else under the app host.
    $machinePath = if ($Rule.ConfigSection -match '/system.web/') { 'MACHINE/WEBROOT' } else { 'MACHINE/WEBROOT/APPHOST' }
    $websitePath = Get-AnsibleIisScopePath -StigId $StigId -MachinePath $machinePath -TaskId $Rule.Id -StigName $StigName

    @{
        GroupDetail = 'Ensure section {0} is configured' -f $parsedConfigSection
        Task = @(
            @{
                Detail = 'Ensure {0} is set to {1} on section {2}' -f $Rule.Value, $Rule.Key, $parsedConfigSection
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = [ordered] @{
                        'resource_name' = 'WebConfigProperty'
                        'WebsitePath' = $websitePath
                        'Filter' = $Rule.ConfigSection
                        'PropertyName' = $Rule.Key
                        'Value' = $Rule.Value
                    }
                }
            }
        )
    }
}
