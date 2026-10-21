function Build-AnsiblePermissionTask {
    <#
    .SYNOPSIS
        One win_acl task per access control entry on the rule - or, on a key only SYSTEM can
        read, a script setting the same entry.
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
    $systemOnly = $Rule.Path -match '^(HKLM:|HKEY_LOCAL_MACHINE)\\(?<key>(SECURITY|SAM)(\\.*)?)$'
    $systemKey = if ($systemOnly) { $Matches.key }

    # Administrators hold only READ_CONTROL and WRITE_DAC there, which win_acl asks for more than,
    # so the key is opened for those two alone. See docs/adr/0023.
    $systemKeyScript = @(
        '[CmdletBinding(SupportsShouldProcess)]'
        'param ([string] $Key, [string] $Identity, [string] $Rights, [string] $Type, [string] $Inheritance, [string] $Propagation)'
        '$access = [System.Security.AccessControl.RegistryRights] "ReadPermissions, ChangePermissions"'
        '$handle = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Key, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $access)'
        'if (-not $handle) { throw "HKLM:\$Key does not exist" }'
        'try {'
        '    $acl = $handle.GetAccessControl()'
        '    $before = $acl.Sddl'
        '    $acl.AddAccessRule([System.Security.AccessControl.RegistryAccessRule]::new($Identity,'
        '        [System.Security.AccessControl.RegistryRights] $Rights, [System.Security.AccessControl.InheritanceFlags] $Inheritance,'
        '        [System.Security.AccessControl.PropagationFlags] $Propagation, [System.Security.AccessControl.AccessControlType] $Type))'
        '    $Ansible.Changed = $acl.Sddl -ne $before'
        '    if ($Ansible.Changed -and $PSCmdlet.ShouldProcess("HKLM:\$Key")) { $handle.SetAccessControl($acl) }'
        '} finally { $handle.Close() }'
    ) -join "`n"

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

                # A STIG that does not say otherwise is granting, not denying.
                $type = if ([string]::IsNullOrEmpty($entry.Type)) { 'Allow' } else { $entry.Type }

                $body = if ($systemOnly) {
                    [ordered] @{
                        'ansible.windows.win_powershell' = [ordered] @{
                            'script' = $systemKeyScript
                            'parameters' = [ordered] @{
                                'Key' = $systemKey
                                'Identity' = $principal
                                'Rights' = $entry.Rights
                                'Type' = $type
                                'Inheritance' = [string] $flags.InheritanceFlag
                                'Propagation' = [string] $flags.PropagationFlag
                            }
                        }
                    }
                }
                else {
                    [ordered] @{
                        'ansible.windows.win_acl' = [ordered] @{
                            'path' = if ($wildcard) { '{{ item.path }}' } else { $path }
                            'user' = $principal
                            'rights' = $entry.Rights
                            'type' = $type
                            'inherit' = $flags.InheritanceFlag
                            'propagation' = $flags.PropagationFlag
                        }
                    }
                }
                if ($wildcard) { $body['loop'] = '{{ ' + $filesName + '.files }}' }

                @{
                    Detail = 'Set {0} permissions for {1} on {2}' -f $entry.Rights, $entry.Principal, $Rule.Path
                    Body = $body
                }
            }
        )
    }
}
