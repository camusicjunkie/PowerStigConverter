function Build-AnsibleSecurityOptionTask {
    <#
    .SYNOPSIS
        One security option, as win_security_policy takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # The section and key live in SecurityOptionData.psd1, not on the rule.
    $optionName = $Rule.OptionName -replace '/|\s', '_' -replace ':'

    @{
        Task = @(
            @{
                Detail = $Rule.OptionName
                Body = [ordered] @{
                    'community.windows.win_security_policy' = [ordered] @{
                        'section' = $script:securityOptionData[$optionName].Section
                        'key' = $script:securityOptionData[$optionName].Value
                        'value' = $Resolution.Value
                    }
                }
            }
        )
    }
}
