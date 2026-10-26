function Build-AnsibleMimeTypeTask {
    <#
    .SYNOPSIS
        One IIS MIME type mapping, through win_dsc.
    #>
    param ($Rule, $StigProfile, $Resolution)

    $parsedMimeType = if (Test-PowerStigSubRuleId -Id $Rule.Id) { Get-PowerStigPathLeaf -Path $Rule.MimeType } else { $Rule.MimeType }

    $scope = Get-AnsibleIisScope -MachinePath 'MACHINE/WEBROOT/APPHOST' -StigProfile $StigProfile

    $body = [ordered] @{
        'ansible.windows.win_dsc' = [ordered] @{
            'resource_name' = 'IISMimeTypeMapping'
            'ConfigurationPath' = $scope.Path
            'Extension' = $Rule.Extension
            'MimeType' = $Rule.MimeType
            'Ensure' = $Rule.Ensure
        }
    }

    # A machine-wide scope is one write, so it has nothing to loop over.
    if ($scope.Loop) { $body['loop'] = $scope.Loop }

    @{
        GroupDetail = 'Ensure {0} MIME types are set' -f $parsedMimeType
        RoleVariable = $scope.RoleVariable
        Task = @(
            @{
                Detail = 'Ensure {0} for {1} is {2}' -f $Rule.Extension, $Rule.MimeType, $Rule.Ensure
                Body = $body
            }
        )
    }
}
