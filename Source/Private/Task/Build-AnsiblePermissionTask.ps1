function Build-AnsiblePermissionTask {
    <#
    .SYNOPSIS
        One win_acl task per access control entry on the rule.
    .DESCRIPTION
        The path is emitted exactly as the STIG wrote it, environment variables and all. win_acl
        expands them on the target, which is the only machine whose filesystem the rule is about.
        See docs/adr/0005.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    @{
        # Always a block, because one rule sets several entries on the same path.
        Group = $true
        GroupDetail = 'Set permissions on {0}' -f $Rule.Path
        Task = @(
            foreach ($entry in $Rule.AccessControlEntry.Entry) {
                $flags = Get-AnsibleInheritanceFlag -Resource $Rule.DscResource -Inheritance $entry.Inheritance

                @{
                    Detail = 'Set {0} permissions for {1} on {2}' -f $entry.Rights, $entry.Principal, $Rule.Path
                    Body = [ordered] @{
                        'ansible.windows.win_acl' = [ordered] @{
                            'path' = $Rule.Path
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
