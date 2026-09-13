function Build-AnsibleWebAppPoolTask {
    <#
    .SYNOPSIS
        One application pool property, through win_dsc, over every pool the role names.
    .DESCRIPTION
        PowerStig unions these rules into one xWebAppPool block the way it does SslSettings, but
        only incidentally: each rule sets a different property and the resource writes only the
        parameters it was passed, so a task per rule leaves the other four properties alone and no
        shared handler is needed. See #53.

        The STIG asks for each application pool, not one, so the pool comes from a role-scoped
        list the site fills in rather than a per-rule variable.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $pools = Get-AnsibleRoleVariableReference -TaskName 'webapppools' -StigName $StigName

    # PowerStig writes a rule's own Value as PowerShell source for the resource block it builds as
    # a string, so a boolean arrives as the literal $true and rapidFailProtection is a [Boolean]
    # DSC parameter. The quoted organization values are unquoted in
    # Resolve-AnsibleOrganizationValue instead - a generator only ever sees their reference.
    $value = switch ($Resolution.Value) {
        '$true' { $true }
        '$false' { $false }
        default { $Resolution.Value }
    }

    $dsc = [ordered] @{
        'resource_name' = 'WebAppPool'
        # A bare pool name, which is what the resource's Name parameter takes.
        'Name' = '{{ item }}'
    }
    $dsc[$Rule.Key] = $value

    @{
        Task = @(
            @{
                Detail = 'Ensure {0}' -f $Rule.Key
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = $dsc
                    'loop' = $pools
                }
            }
        )
    }
}
