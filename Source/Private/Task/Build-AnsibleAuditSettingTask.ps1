function Build-AnsibleAuditSettingTask {
    <#
    .SYNOPSIS
        One WMI audit, through win_dsc - there is no ansible module covering it.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $dsc = [ordered] @{
        'resource_name' = 'AuditSetting'
        'Query' = $Rule.Query
        'Property' = $Rule.Property
        'DesiredValue' = $Rule.DesiredValue
        'Operator' = $Rule.Operator
    }

    # The resource defaults the namespace itself, so sending an empty one is worse than none.
    if ($Rule.Namespace) { $dsc.Namespace = $Rule.Namespace }

    @{
        Task = @(
            @{
                Detail = 'Audit that {0} {1} {2}' -f $Rule.Property, $Rule.Operator, $Rule.DesiredValue
                Body = [ordered] @{ 'ansible.windows.win_dsc' = $dsc }
            }
        )
    }
}
