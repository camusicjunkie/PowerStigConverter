function Build-AnsibleAccountPolicyTask {
    <#
    .SYNOPSIS
        One account policy, as win_security_policy takes it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # The section and key live in AccountPolicyData.psd1, not on the rule.
    $policyName = $Rule.PolicyName -replace '/|\s', '_' -replace ':'
    $policyValue = $Resolution.Value
    $parsedPolicyValue = if ([int32]::TryParse($policyValue, [ref] $null)) { [int] $policyValue } else { $policyValue }

    @{
        Task = @(
            @{
                Detail = $Rule.PolicyName
                Body = [ordered] @{
                    'community.windows.win_security_policy' = [ordered] @{
                        'section' = $script:accountPolicyData[$policyName].Section
                        'key' = $script:accountPolicyData[$policyName].Value
                        'value' = $parsedPolicyValue
                    }
                }
            }
        )
    }
}
