function Build-AnsibleAccountPolicyTask {
    <#
    .SYNOPSIS
        One account policy, as win_security_policy takes it.
    .DESCRIPTION
        On a domain member the domain owns account policy, so outside a domain controller the task
        runs only off a domain. On a domain controller secedit's write is the domain's policy. A
        STIG profile's Target says whether it targets one. The lockout threshold is
        marked First, since duration and reset exist only once it is above 0. See #232.

        A DC's Kerberos policy is the exception: a local write does not take, so it is set in the
        Default Domain Policy's template. See docs/adr/0028.
    #>
    param ($Rule, $StigProfile, $Resolution)

    $infOption = Resolve-AnsibleInfOption -OptionName $Rule.PolicyName
    $policyValue = $Resolution.Value
    $parsedPolicyValue = if ([int32]::TryParse($policyValue, [ref] $null)) { [int] $policyValue } else { $policyValue }

    if ($StigProfile.Target -eq 'DomainController' -and $infOption.Section -eq 'Kerberos Policy') {
        return @{
            First = $infOption.First
            Task = @(
                @{
                    Detail = $Rule.PolicyName
                    Body = [ordered] @{
                        'ansible.windows.win_powershell' = [ordered] @{
                            'script' = $script:defaultDomainPolicyScript
                            'parameters' = [ordered] @{
                                'Section' = $infOption.Section
                                'Key' = $infOption.Key
                                'Value' = $parsedPolicyValue
                            }
                        }
                    }
                }
            )
        }
    }

    $body = [ordered] @{
        'community.windows.win_security_policy' = [ordered] @{
            'section' = $infOption.Section
            'key' = $infOption.Key
            'value' = $parsedPolicyValue
        }
    }
    if ($StigProfile.Target -ne 'DomainController') { $body['when'] = "not $script:domainMemberCondition" }

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
