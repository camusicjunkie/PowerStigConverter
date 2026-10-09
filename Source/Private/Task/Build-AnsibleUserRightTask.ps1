function Build-AnsibleUserRightTask {
    <#
    .SYNOPSIS
        One user right, as win_user_right takes it.
    .DESCRIPTION
        PowerStig ends some identities with a sentence period ('Administrators.'), which the
        module cannot translate to a SID, so a literal list is stripped of it. win_user_right
        also crashes on an empty users list (it pipes the list into a mandatory-string function),
        so a right nobody may hold is built as gather-the-holders then remove them. See #143.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $right = $Rule.Constant
    $users = $Resolution.Value

    if ($users -is [array]) {
        $users = @($users | ForEach-Object { ([string] $_).Trim() -replace '(?<=.)\.$' })
    }

    if ($null -eq $users -or ($users -is [array] -and $users.Count -eq 0)) {
        $registerName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigName $StigName -Suffix 'holders'

        # secedit omits the line for a right nobody holds; entries are *SID or an account name,
        # both of which win_user_right resolves.
        $script = @(
            '$cfg = [IO.Path]::GetTempFileName()'
            'try {'
            '    $null = secedit.exe /export /cfg $cfg /areas USER_RIGHTS'
            '    $line = Get-Content -LiteralPath $cfg | Where-Object { $_ -match "^RIGHT\s*=" }'.Replace('RIGHT', $right)
            '    $Ansible.Result = @(if ($line) { ($line -split "=", 2)[1] -split "," | ForEach-Object { $_.Trim().TrimStart("*") } | Where-Object { $_ } })'
            '} finally { Remove-Item -LiteralPath $cfg -ErrorAction SilentlyContinue }'
        ) -join "`n"

        return @{
            Group = $true
            GroupDetail = 'Ensure no one holds {0}' -f $Rule.DisplayName
            Task = @(
                @{
                    Name = 'Gather the holders of {0}' -f $Rule.DisplayName
                    Body = [ordered] @{
                        'ansible.windows.win_powershell' = [ordered] @{ 'script' = $script }
                        'register' = $registerName
                        # Read-only, so it runs under --check and never reports a change.
                        'check_mode' = $false
                        'changed_when' = $false
                    }
                }
                @{
                    Name = 'Remove every holder of {0}' -f $Rule.DisplayName
                    Body = [ordered] @{
                        'ansible.windows.win_user_right' = [ordered] @{
                            'name' = $right
                            'action' = 'remove'
                            'users' = "{{ $registerName.result }}"
                        }
                        'when' = "$registerName.result | length > 0"
                    }
                }
            )
        }
    }

    @{
        Task = @(
            @{
                Detail = $Rule.DisplayName
                Body = [ordered] @{
                    'ansible.windows.win_user_right' = [ordered] @{
                        # win_user_right takes the constant, not the display name a human reads.
                        'name' = $right
                        # A rule that forces the list replaces whoever holds the right.
                        'action' = if ($Rule.Force -eq 'True') { 'set' } else { 'add' }
                        'users' = $users
                    }
                }
            }
        )
    }
}
