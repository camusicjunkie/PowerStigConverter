function Build-AnsibleUserRightTask {
    <#
    .SYNOPSIS
        One user right, as win_user_right takes it.
    .DESCRIPTION
        PowerStig ends some identities with a sentence period ('Administrators.'), which the
        module cannot translate to a SID, so a literal list is stripped of it. win_user_right
        also crashes on an empty users list (it pipes the list into a mandatory-string function),
        so a right nobody may hold is built as gather-the-holders then remove them. See #143.
        A domain-only identity is added only on a domain member. See docs/adr/0025.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $right = $Rule.Constant
    $users = $Resolution.Value

    if ($users -is [array]) {
        # Trimmed again after the strip: PowerStig writes 'Local account .'.
        $users = @($users | ForEach-Object { (([string] $_).Trim() -replace '(?<=.)\.$').Trim() })
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

    $body = [ordered] @{
        'ansible.windows.win_user_right' = [ordered] @{
            # win_user_right takes the constant, not the display name a human reads.
            'name' = $right
            # A rule that forces the list replaces whoever holds the right.
            'action' = if ($Rule.Force -eq 'True') { 'set' } else { 'add' }
            'users' = $users
        }
    }

    # Only a literal list is split; an organization value is a reference. See docs/adr/0025.
    $split = if ($users -is [array]) { Split-AnsibleUserRightIdentity -Rule $Rule -Identity $users -StigName $StigName }
    if ($split -and $split.Domain.Count -gt 0) {
        $member = "ansible_facts['windows_domain_member']"
        if ($split.All.Count -gt 0) {
            $body['ansible.windows.win_user_right']['users'] = '{{{{ {0} + ({1} if {2} else []) }}}}' -f
                (ConvertTo-AnsibleJinjaList $split.All), (ConvertTo-AnsibleJinjaList $split.Domain), $member
        }
        else {
            $body['when'] = $member
        }
    }

    @{
        Task = @(
            @{
                Detail = $Rule.DisplayName
                Body = $body
            }
        )
    }
}

<#
.SYNOPSIS
    A rule's identities sorted into DISA's Domain Systems Only and All Systems lists, or nothing
    when its check text has no Domain Systems Only heading.
.DESCRIPTION
    Each section runs to the next blank line. An identity belongs to the section holding a line
    that starts with it, since DISA writes 'Enterprise Admins group' for 'Enterprise Admins'. One
    in neither section or both fails the conversion: the fix is RuleCorrection.psd1 (ADR 0020).
#>
function Split-AnsibleUserRightIdentity {
    param ($Rule, [string[]] $Identity, [string] $StigName)

    $domainHeading, $allHeading = 'Domain Systems Only:', 'All Systems:'
    $lines = @(([string] $Rule.RawString) -split '\r?\n' | ForEach-Object { $_.Trim() })
    if ($lines -notcontains $domainHeading) { return }

    $section = @{ $domainHeading = @(); $allHeading = @() }
    $current = $null
    foreach ($line in $lines) {
        if ($section.ContainsKey($line)) { $current = $line; continue }
        if ($line -eq '') { $current = $null; continue }
        # Server STIGs bullet each line with '- '.
        if ($current) { $section[$current] += $line -replace '^-\s*' }
    }

    $domain = @(); $all = @()
    foreach ($name in $Identity) {
        $inDomain, $inAll = foreach ($heading in $domainHeading, $allHeading) {
            @($section[$heading] | Where-Object { $_.StartsWith($name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        }

        if ($inDomain -eq $inAll) {
            $where = if ($inDomain) { 'both' } else { 'neither' }
            throw ("{0} {1}: identity '{2}' is under {3} of the check text's '{4}' and '{5}' headings. Correct the rule in RuleCorrection.psd1 (docs/adr/0020)." -f
                $StigName, $Rule.Id, $name, $where, $domainHeading, $allHeading)
        }
        if ($inDomain) { $domain += $name } else { $all += $name }
    }

    @{ Domain = $domain; All = $all }
}

<#
.SYNOPSIS
    A list of strings as a jinja list literal.
#>
function ConvertTo-AnsibleJinjaList {
    param ([string[]] $Item)

    '[{0}]' -f (($Item | ForEach-Object { "'{0}'" -f ($_ -replace "'", "\'") }) -join ', ')
}
