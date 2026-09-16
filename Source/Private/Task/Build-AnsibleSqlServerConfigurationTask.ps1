function Build-AnsibleSqlServerConfigurationTask {
    <#
    .SYNOPSIS
        One sp_configure option set to the value the rule names, through win_dsc, on every instance
        the role names.
    .DESCRIPTION
        The resource is SqlConfiguration, not SqlServerConfiguration: SqlServerDsc renamed it in
        v15 and this is the one rule type whose PowerStig name and DSC resource name diverge. The
        function keeps the long name because ConvertTo-AnsibleTask derives the adapter from the
        rule type - do not "fix" either half to match the other.

        The rule carries only OptionName and OptionValue. InstanceName is a site fact no STIG
        states, so it comes from the role-scoped list every Sql* generator shares; ServerName,
        credentials and RestartTimeout are left off, the resource's own defaults being about the
        target rather than anything the rule says. See #66.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $instances = Get-AnsibleRoleVariableReference -TaskName 'instances' -StigName $StigName

    # PowerStig hands the value over as a string and powershell-yaml quotes that, so a
    # pass-through would emit OptionValue: "0". No fallback: the property is Required/SInt32, so a
    # non-numeric value is a malformed rule and should fail here rather than on the target.
    $optionValue = [int] $Rule.OptionValue

    @{
        RoleVariable = 'instances'
        Task = @(
            @{
                Detail = 'Set {0} to {1}' -f $Rule.OptionName, $optionValue
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = [ordered] @{
                        'resource_name' = 'SqlConfiguration'
                        'InstanceName' = '{{ item }}'
                        'OptionName' = $Rule.OptionName
                        'OptionValue' = $optionValue
                        # Some of these options are inert until the instance restarts and the
                        # resource defaults this off, so the write would report changed and leave
                        # the instance non-compliant. It restarts only when Set changed a value.
                        'RestartService' = $true
                    }
                    'loop' = $instances
                }
            }
        )
    }
}
