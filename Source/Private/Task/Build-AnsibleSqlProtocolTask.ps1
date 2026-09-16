function Build-AnsibleSqlProtocolTask {
    <#
    .SYNOPSIS
        One network protocol enabled or disabled, through win_dsc, on every instance the role names.
    .DESCRIPTION
        SqlServerDsc's SqlProtocol keys on InstanceName and ProtocolName both, and the rule states
        the protocol, so one task per rule loops the role-scoped instances list. InstanceName is a
        site fact no STIG states; ServerName is left off for the reason every Sql* generator leaves
        it off. See #62.

        SuppressRestart is omitted so the resource restarts the instance itself: it does that
        through Restart-SqlService, which is cluster-aware, and a win_service handler could only
        match it by encoding service names this converter has no business asserting (ADR-0005).
        See #64.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $instances = Get-AnsibleRoleVariableReference -TaskName 'instances' -StigName $StigName

    # PowerStig hands the flag over as the text 'True'/'False', which powershell-yaml would quote.
    # An explicit comparison, never a cast - [bool] 'False' is $true. See #64 and #69.
    $enabled = $Rule.Enabled -eq 'True'

    @{
        RoleVariable = 'instances'
        Task = @(
            @{
                # Derived from the rule, so it stays true if a revision flips the protocol or flag.
                Detail = 'Ensure the {0} protocol is {1}' -f $Rule.ProtocolName, $(if ($enabled) { 'enabled' } else { 'disabled' })
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = [ordered] @{
                        'resource_name' = 'SqlProtocol'
                        'InstanceName' = '{{ item }}'
                        'ProtocolName' = $Rule.ProtocolName
                        'Enabled' = $enabled
                    }
                    'loop' = $instances
                }
            }
        )
    }
}
