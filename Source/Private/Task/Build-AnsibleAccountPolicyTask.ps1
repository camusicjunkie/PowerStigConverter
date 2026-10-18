function Build-AnsibleAccountPolicyTask {
    <#
    .SYNOPSIS
        One account policy, as win_security_policy takes it.
    .DESCRIPTION
        On a domain controller the lockout duration and reset counter are the domain's, which
        secedit will not take, so those two set the Default Domain Policy instead. A rule's
        product name ending in -DC is what says it targets one. See #175.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $infOption = Resolve-AnsibleInfOption -OptionName $Rule.PolicyName
    $policyValue = $Resolution.Value
    $parsedPolicyValue = if ([int32]::TryParse($policyValue, [ref] $null)) { [int] $policyValue } else { $policyValue }

    $domainParameter = @{ LockoutDuration = 'LockoutDuration'; ResetLockoutCount = 'LockoutObservationWindow' }[$infOption.Key]
    if ($StigName -match '-DC$' -and $domainParameter) {
        # Read-then-set so a run that finds the policy already right reports no change.
        $script = @(
            'param ([int] $Minutes)'
            '$want = [TimeSpan]::FromMinutes($Minutes)'
            '$domain = Get-ADDomain'
            '$current = Get-ADDefaultDomainPasswordPolicy -Identity $domain.DNSRoot'
            'if ($current.PARAM -ne $want) {'
            '    if (-not $Ansible.CheckMode) { Set-ADDefaultDomainPasswordPolicy -Identity $domain.DNSRoot -PARAM $want }'
            '    $Ansible.Changed = $true'
            '} else { $Ansible.Changed = $false }'
        ).Replace('PARAM', $domainParameter) -join "`n"

        return @{
            Task = @(
                @{
                    Detail = $Rule.PolicyName
                    Body = [ordered] @{
                        'ansible.windows.win_powershell' = [ordered] @{
                            'script' = $script
                            'parameters' = [ordered] @{ 'Minutes' = $parsedPolicyValue }
                        }
                    }
                }
            )
        }
    }

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
