function Build-AnsibleWebConfigurationPropertyTask {
    <#
    .SYNOPSIS
        One IIS web configuration property, through win_dsc.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $parsedConfigSection = if (Test-PowerStigSubRuleId -Id $Rule.Id) { Get-PowerStigPathLeaf -Path $Rule.ConfigSection } else { $Rule.ConfigSection }

    # A system.web section lives under the web root, everything else under the app host.
    $machinePath = if ($Rule.ConfigSection -match '/system.web/') { 'MACHINE/WEBROOT' } else { 'MACHINE/WEBROOT/APPHOST' }
    $scope = Get-AnsibleIisScope -StigId $StigId -MachinePath $machinePath -StigName $StigName

    $body = [ordered] @{
        'ansible.windows.win_dsc' = [ordered] @{
            'resource_name' = 'WebConfigProperty'
            'WebsitePath' = $scope.Path
            'Filter' = $Rule.ConfigSection
            'PropertyName' = $Rule.Key
            'Value' = $Rule.Value
        }
    }

    # A machine-wide scope is one write, so it has nothing to loop over.
    if ($scope.Loop) { $body['loop'] = $scope.Loop }

    @{
        GroupDetail = 'Ensure section {0} is configured' -f $parsedConfigSection
        RoleVariable = $scope.RoleVariable
        Task = @(
            @{
                Detail = 'Ensure {0} is set to {1} on section {2}' -f $Rule.Value, $Rule.Key, $parsedConfigSection
                Body = $body
            }
        )
    }
}
