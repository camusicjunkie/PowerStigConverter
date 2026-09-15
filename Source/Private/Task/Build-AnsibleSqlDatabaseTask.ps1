function Build-AnsibleSqlDatabaseTask {
    <#
    .SYNOPSIS
        One database present or absent, through win_dsc, on every instance the role names.
    .DESCRIPTION
        The rule carries only Name and Ensure. InstanceName is a site fact no STIG states, so it
        comes from the role-scoped list every Sql* generator shares rather than a per-rule
        variable. ServerName is left off: SqlServerDsc defaults it to the local machine, which is
        where win_dsc already runs. See #62.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $instances = Get-AnsibleRoleVariableReference -TaskName 'instances' -StigName $StigName

    @{
        RoleVariable = 'instances'
        # Group-AnsibleTask keeps the first sub-rule's group name, so this is derived from Ensure
        # alone - the only field .a-.d share.
        GroupDetail = 'Ensure the databases are {0}' -f $Rule.Ensure.ToLower()
        Task = @(
            @{
                Detail = 'Ensure {0} is {1}' -f $Rule.Name, $Rule.Ensure.ToLower()
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = [ordered] @{
                        'resource_name' = 'SqlDatabase'
                        'InstanceName' = '{{ item }}'
                        'Name' = $Rule.Name
                        'Ensure' = $Rule.Ensure
                    }
                    'loop' = $instances
                }
            }
        )
    }
}
