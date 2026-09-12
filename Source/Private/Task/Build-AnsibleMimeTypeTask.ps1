function Build-AnsibleMimeTypeTask {
    <#
    .SYNOPSIS
        One IIS MIME type mapping, through win_dsc.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $parsedMimeType = if (Test-PowerStigSubRuleId -Id $Rule.Id) { Split-Path -Path $Rule.MimeType } else { $Rule.MimeType }

    $configurationPath = Get-AnsibleIisScopePath -StigId $StigId -MachinePath 'MACHINE/WEBROOT/APPHOST' `
        -TaskId $Rule.Id -StigName $StigName

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
