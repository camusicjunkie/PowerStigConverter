function Build-AnsiblePermissionTask {
    <#
    .SYNOPSIS
        One win_acl task per access control entry on the rule.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $parsedPath = [System.Environment]::ExpandEnvironmentVariables($Rule.Path)
    # Whether the expanded path exists is asked of the converting machine, not the target. See #8.
    $path = if (Test-Path $parsedPath) { $parsedPath } else { $Rule.Path }

    @{
        # Always a block, because one rule sets several entries on the same path.
        Group = $true
        GroupDetail = 'Set permissions on {0}' -f $parsedPath
        Task = @(
            foreach ($entry in $Rule.AccessControlEntry.Entry) {
                $flags = Get-AnsibleInheritanceFlag -Resource $Rule.DscResource -Inheritance $entry.Inheritance

                @{
                    Detail = 'Set {0} permissions for {1} on {2}' -f $entry.Rights, $entry.Principal, $parsedPath
                    Body = [ordered] @{
                        'ansible.windows.win_acl' = [ordered] @{
                            'path' = $path
                            'user' = $entry.Principal
                            'rights' = $entry.Rights
                            # A STIG that does not say otherwise is granting, not denying.
                            'type' = if ([string]::IsNullOrEmpty($entry.Type)) { 'Allow' } else { $entry.Type }
                            'inherit' = $flags.InheritanceFlag
                            'propagation' = $flags.PropagationFlag
                        }
                    }
                }
            }
        )
    }
}
