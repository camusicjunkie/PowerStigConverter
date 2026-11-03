function Build-AnsibleAuditPolicyTask {
    <#
    .SYNOPSIS
        The audit policy subcategory and flag, as win_audit_policy_system takes them.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Every generator takes the parameters ConvertTo-AnsibleTask passes all of them')]
    param ($Rule, $StigProfile, $Resolution)

    @{
        Task = @(
            @{
                Detail = '{0} - {1}' -f $Rule.Subcategory, $Rule.AuditFlag
                Body = [ordered] @{
                    'ansible.windows.win_audit_policy_system' = [ordered] @{
                        'subcategory' = $Rule.Subcategory
                        'audit_type' = $Rule.AuditFlag
                    }
                }
            }
        )
    }
}
