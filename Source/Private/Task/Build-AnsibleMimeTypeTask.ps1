function Build-AnsibleMimeTypeTask {
    <#
    .SYNOPSIS
        One IIS MIME type mapping, through win_dsc.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $parsedMimeType = if ($Rule.Id -match '\.[a-z]$') { Split-Path -Path $Rule.MimeType } else { $Rule.MimeType }

    # A server STIG configures the machine-wide root; a site STIG configures one site.
    $website = ''
    $configurationPath = if ($StigId -match 'IIS_.+_Server') { 'MACHINE/WEBROOT/APPHOST' } else { "IIS:\Sites\$website" }

    @{
        GroupDetail = 'Ensure {0} MIME types are set' -f $parsedMimeType
        Task = @(
            @{
                Detail = 'Ensure {0} for {1} is {2}' -f $Rule.Extension, $Rule.MimeType, $Rule.Ensure
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = [ordered] @{
                        'resource_name' = 'IISMimeTypeMapping'
                        'ConfigurationPath' = $configurationPath
                        'Extension' = $Rule.Extension
                        'MimeType' = $Rule.MimeType
                        'Ensure' = $Rule.Ensure
                    }
                }
            }
        )
    }
}
