function Build-AnsibleAccountPolicyTask {
    <#
    .SYNOPSIS
        One account policy, as win_security_policy takes it.
    .DESCRIPTION
        On a domain member the domain owns account policy, so outside a domain controller the task
        runs only off a domain. On a domain controller secedit's write is the domain's policy. A
        rule's product name ending in -DC is what says it targets one. The lockout threshold is
        marked First, since duration and reset exist only once it is above 0. See #232.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $infOption = Resolve-AnsibleInfOption -OptionName $Rule.PolicyName
    $policyValue = $Resolution.Value
    $parsedPolicyValue = if ([int32]::TryParse($policyValue, [ref] $null)) { [int] $policyValue } else { $policyValue }

    $body = [ordered] @{
        'community.windows.win_security_policy' = [ordered] @{
            'section' = $infOption.Section
            'key' = $infOption.Key
            'value' = $parsedPolicyValue
        }
    }
    if ($StigName -notmatch '-DC$') { $body['when'] = "not $script:domainMemberCondition" }

    @{
        First = $infOption.First
        Task = @(
            @{
                Detail = $Rule.PolicyName
                Body = $body
            }
        )
    }
}
