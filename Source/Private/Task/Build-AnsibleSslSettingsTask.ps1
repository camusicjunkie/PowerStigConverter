function Build-AnsibleSslSettingsTask {
    <#
    .SYNOPSIS
        One rule's contribution to a site's SSL flags, applied once from a shared handler.
    .DESCRIPTION
        The SslSettings DSC resource writes sslFlags wholesale - Ensure Present means "the flags
        are exactly these" - so a win_dsc task per rule would have each rule undo the last, the
        CAT 1 rule included. PowerStig unions the rules' values and writes once per website for
        the same reason; the difference is only that it can do it at compile time, where a
        generated role has to defer the write until run time because a toggle is an operator's
        to flip. Hence: every rule contributes its flags to one list and notifies one handler.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $flags = @($Rule.Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $flagList = Get-AnsibleRoleVariableName -TaskName 'sslflags' -StigName $StigName
    $websites = Get-AnsibleRoleVariableReference -TaskName 'websites' -StigName $StigName

    # default([]) rather than a declaration in defaults/: the list is the tasks' own running
    # total, not a blank for the site to fill in the way the website list is.
    $contribution = '{{{{ ({0} | default([])) + [{1}] }}}}' -f $flagList,
        (($flags | ForEach-Object { "'{0}'" -f ($_ -replace "'", "''") }) -join ', ')

    @{
        Task = @(
            @{
                Detail = 'Ensure SSL settings include {0}' -f ($flags -join ', ')
                Body = [ordered] @{
                    'ansible.builtin.set_fact' = [ordered] @{ $flagList = $contribution }
                    # set_fact never reports changed, so a bare notify would never fire. The cost
                    # is a task that always reports changed; the win_dsc write it notifies stays
                    # honestly idempotent.
                    'changed_when' = $true
                    'notify' = 'apply_ssl_settings'
                }
            }
        )
        Handler = @{
            # Named outright, and the same for every rule: notify reaches a handler by name.
            Name = 'apply_ssl_settings'
            Body = [ordered] @{
                'ansible.windows.win_dsc' = [ordered] @{
                    'resource_name' = 'SslSettings'
                    # A bare site name, not the IIS:\Sites\ path Get-AnsibleIisScopePath builds.
                    'Name' = '{{ item }}'
                    'Bindings' = '{{{{ {0} | unique }}}}' -f $flagList
                    'Ensure' = 'Present'
                }
                'loop' = $websites
            }
        }
    }
}
