function Build-AnsibleWebConfigurationPropertyTask {
    <#
    .SYNOPSIS
        One IIS web configuration property, through win_dsc.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $parsedConfigSection = if ($Rule.Id -match '\.[a-z]$') { Split-Path -Path $Rule.ConfigSection } else { $Rule.ConfigSection }
    $website = Get-AnsibleVariableReference -TaskId $Rule.Id -TaskName 'website' -StigName $StigName

    # A system.web section lives under the web root, everything else under the app host. A site
    # STIG instead targets one site, whose name the implementing site fills in.
    $websitePath = if ($StigId -match 'IIS_.+_Server') {
        if ($Rule.ConfigSection -match '/system.web/') { 'MACHINE/WEBROOT' } else { 'MACHINE/WEBROOT/APPHOST' }
    }
    else {
        "IIS:\Sites\$website"
    }

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
