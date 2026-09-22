function Build-AnsibleSecurityOptionTask {
    <#
    .SYNOPSIS
        One security option, as win_security_policy takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $infOption = Resolve-AnsibleInfOption -OptionName $Rule.OptionName

    @{
        Task = @(
            @{
                Detail = $Rule.OptionName
                Body = [ordered] @{
                    'community.windows.win_security_policy' = [ordered] @{
                        'section' = $infOption.Section
                        'key' = $infOption.Key
                        'value' = $Resolution.Value
                    }
                }
            }
        )
    }
}
