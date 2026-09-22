function Build-AnsibleAccountPolicyTask {
    <#
    .SYNOPSIS
        One account policy, as win_security_policy takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $infOption = Resolve-AnsibleInfOption -OptionName $Rule.PolicyName
    $policyValue = $Resolution.Value
    $parsedPolicyValue = if ([int32]::TryParse($policyValue, [ref] $null)) { [int] $policyValue } else { $policyValue }

    @{
        Task = @(
            @{
                Detail = $Rule.PolicyName
                Body = [ordered] @{
                    'community.windows.win_security_policy' = [ordered] @{
                        'section' = $infOption.Section
                        'key' = $infOption.Key
                        'value' = $parsedPolicyValue
                    }
                }
            }
        )
    }
}
