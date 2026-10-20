function Build-AnsiblePermissionTask {
    <#
    .SYNOPSIS
        One win_acl task per access control entry on the rule.
    .DESCRIPTION
        A %Var% in the path resolves on the target, through the env fact the role's tasks/main.yml
        sets: win_acl takes its path literally, and the converting machine's environment is not
        the target's. The task name keeps the path as the STIG wrote it. See docs/adr/0017.

        win_acl takes a path literally, so a path ending in a wildcard ('%windir%\NTDS\*.*') is
        searched for on the target and each entry applied to every file found. See #173.

        A rule left with no entry builds nothing - RuleCorrection.psd1 removes an entry PowerStig
        misparsed, such as '(RX)'. See docs/adr/0020.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $entries = @($Rule.AccessControlEntry.Entry | Where-Object { $_ })
    if ($entries.Count -eq 0) { return }

    # Windows resolves these service accounts only under NT SERVICE (issue #144).
    $servicePrincipal = @{ trustedinstaller = 'NT SERVICE\TrustedInstaller'; eventlog = 'NT SERVICE\EventLog' }

    $fact = Get-AnsibleFactName -Name 'env' -StigName $StigName
    $resolve = {
        param ($text)
        [regex]::Replace($text, '%([^%]+)%', {
            param ($match)
            "{{ $fact['$($match.Groups[1].Value.ToLower())'] }}"
        })
    }

    # The separator is matched literally, as Build-AnsibleRegistryTask does for a key.
    $split = $Rule.Path.LastIndexOf('\')
    $wildcard = $Rule.Path.Substring($split + 1) -match '[*?]'
    $path = & $resolve $(if ($wildcard) { $Rule.Path.Substring(0, $split) } else { $Rule.Path })

    $filesName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigName $StigName -Suffix 'files'

    # SECURITY and SAM are readable only by SYSTEM, and the rule's path says so (issue #147).
    $systemOnly = $Rule.Path -match '^(HKLM:|HKEY_LOCAL_MACHINE)\\(SECURITY|SAM)(\\|$)'

    @{
        # Always a block, because one rule sets several entries on the same path.
        Group = $true
        GroupDetail = 'Set permissions on {0}' -f $Rule.Path
        Task = @(
            if ($wildcard) {
                @{
                    Name = 'Find the files matching {0}' -f $Rule.Path
                    Body = [ordered] @{
                        'ansible.windows.win_find' = [ordered] @{
                            'paths' = $path
                            'patterns' = @($Rule.Path.Substring($split + 1))
                            'file_type' = 'file'
                        }
                        'register' = $filesName
                        # Read-only, so it runs under --check and never reports a change.
                        'check_mode' = $false
                    }
                }
            }
            foreach ($entry in $entries) {
                $flags = Get-AnsibleInheritanceFlag -Resource $Rule.DscResource -Inheritance $entry.Inheritance

                $principal = if ($servicePrincipal.ContainsKey($entry.Principal)) { $servicePrincipal[$entry.Principal] } else { $entry.Principal }

                $task = @{
                    Detail = 'Set {0} permissions for {1} on {2}' -f $entry.Rights, $entry.Principal, $Rule.Path
                    Body = [ordered] @{
                        'ansible.windows.win_acl' = [ordered] @{
                            'path' = if ($wildcard) { '{{ item.path }}' } else { $path }
                            'user' = $principal
                            'rights' = $entry.Rights
                            # A STIG that does not say otherwise is granting, not denying.
                            'type' = if ([string]::IsNullOrEmpty($entry.Type)) { 'Allow' } else { $entry.Type }
                            'inherit' = $flags.InheritanceFlag
                            'propagation' = $flags.PropagationFlag
                        }
                    }
                }
                if ($wildcard) { $task.Body['loop'] = '{{ ' + $filesName + '.files }}' }
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
