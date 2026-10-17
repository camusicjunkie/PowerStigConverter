function Build-AnsiblePermissionTask {
    <#
    .SYNOPSIS
        One win_acl task per access control entry on the rule.
    .DESCRIPTION
        A %Var% in the path resolves on the target, through the env fact the role's tasks/main.yml
        sets: win_acl takes its path literally, and the converting machine's environment is not
        the target's. The task name keeps the path as the STIG wrote it. See docs/adr/0017.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # Windows resolves these service accounts only under NT SERVICE (issue #144).
    $servicePrincipal = @{ trustedinstaller = 'NT SERVICE\TrustedInstaller'; eventlog = 'NT SERVICE\EventLog' }

    $fact = Get-AnsibleFactName -Name 'env' -StigName $StigName
    $path = [regex]::Replace($Rule.Path, '%([^%]+)%', {
        param ($match)
        "{{ $fact['$($match.Groups[1].Value.ToLower())'] }}"
    })

    # SECURITY and SAM are readable only by SYSTEM, and the rule's path says so (issue #147).
    $systemOnly = $Rule.Path -match '^(HKLM:|HKEY_LOCAL_MACHINE)\\(SECURITY|SAM)(\\|$)'

    @{
        # Always a block, because one rule sets several entries on the same path.
        Group = $true
        GroupDetail = 'Set permissions on {0}' -f $Rule.Path
        Task = @(
            foreach ($entry in $Rule.AccessControlEntry.Entry) {
                $flags = Get-AnsibleInheritanceFlag -Resource $Rule.DscResource -Inheritance $entry.Inheritance

                $principal = if ($servicePrincipal.ContainsKey($entry.Principal)) { $servicePrincipal[$entry.Principal] } else { $entry.Principal }

                $task = @{
                    Detail = 'Set {0} permissions for {1} on {2}' -f $entry.Rights, $entry.Principal, $Rule.Path
                    Body = [ordered] @{
                        'ansible.windows.win_acl' = [ordered] @{
                            'path' = $path
                            'user' = $principal
                            'rights' = $entry.Rights
                            # A STIG that does not say otherwise is granting, not denying.
                            'type' = if ([string]::IsNullOrEmpty($entry.Type)) { 'Allow' } else { $entry.Type }
                            'inherit' = $flags.InheritanceFlag
                            'propagation' = $flags.PropagationFlag
                        }
                    }
                }
                # Runs as the account the key admits, with no credential (ADR 0006). The method is named
                # because the default, sudo, is not supported on Windows.
                if ($systemOnly) {
                    $task.Body.become = $true
                    $task.Body.become_user = 'SYSTEM'
                    $task.Body.become_method = 'ansible.builtin.runas'
                }
                $task
            }
        )
    }
}
