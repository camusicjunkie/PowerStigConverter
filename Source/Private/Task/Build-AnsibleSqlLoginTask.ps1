function Build-AnsibleSqlLoginTask {
    <#
    .SYNOPSIS
        The password rules for the SQL logins the organization names, over every instance the role
        names.
    .DESCRIPTION
        SqlServerDsc's SqlLogin keys on InstanceName and Name both, so every instance/login pair is
        its own resource instance - one task loops the Cartesian product of the two lists and
        addresses the pair as item.0 and item.1. Distinct instances, so no shared handler.

        Ensure is left out: the org settings file declares it, but PowerStig's own composite never
        passes it and the rule is about enforcing the password policy on logins that already exist,
        not creating or removing them. See #63.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # product() takes bare variable names, not {{ }} references, so neither list can come through
    # the reference the generators otherwise interpolate.
    $instances = Get-AnsibleRoleVariableName -TaskName 'instances' -StigName $StigName
    $logins = $Resolution.Variable.Name

    @{
        RoleVariable = 'instances'
        Task = @(
            @{
                # Derived from the rule, so it stays true if a revision changes the login type.
                Detail = 'Ensure the {0} logins enforce the password policy' -f $Rule.LoginType
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = [ordered] @{
                        'resource_name' = 'SqlLogin'
                        'InstanceName' = '{{ item.0 }}'
                        'Name' = '{{ item.1 }}'
                        'LoginType' = $Rule.LoginType
                        'LoginPasswordPolicyEnforced' = $Rule.LoginPasswordPolicyEnforced
                        'LoginPasswordExpirationEnabled' = $Rule.LoginPasswordExpirationEnabled
                        'LoginMustChangePassword' = $Rule.LoginMustChangePassword
                    }
                    'loop' = '{{{{ {0} | product({1}) | list }}}}' -f $instances, $logins
                }
            }
        )
    }
}
