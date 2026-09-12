function Build-AnsibleAuditPolicyTask {
    <#
    .SYNOPSIS
        The audit policy subcategory and flag, as win_audit_policy_system takes them.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    @{
        Task = @(
            @{
                Detail = '{0} - {1}' -f $Rule.Subcategory, $Rule.AuditFlag
                Body = [ordered] @{
                    'community.windows.win_audit_policy_system' = [ordered] @{
                        'subcategory' = $Rule.Subcategory
                        'audit_type' = $Rule.AuditFlag
                    }
                }
            }
        )
    }
}
