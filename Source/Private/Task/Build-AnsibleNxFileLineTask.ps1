function Build-AnsibleNxFileLineTask {
    <#
    .SYNOPSIS
        One config line, through lineinfile - or, for the one rule whose ContainsLine is a
        multi-line banner, the whole file through copy. See ADR 0009.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $skipReason = Get-AnsibleNxFileLineSkipReason -Rule $Rule
    if ($skipReason) {
        Write-Warning ('{0}: {1} - skipping. See docs/adr/0009.' -f $Rule.Id, $skipReason)
        return $null
    }

    # PowerStig always writes FilePath forward-slash delimited, regardless of the converting
    # machine's platform, so the leaf is taken by matching that literal character - the same
    # reasoning Build-AnsibleRegistryTask applies to its backslash-delimited keys.
    $leaf = $Rule.FilePath.Substring($Rule.FilePath.LastIndexOf('/') + 1)
    $line = $Resolution.Value.line
    $regexp = $Resolution.Value.regexp

    # V-257779's 13-line DoD banner: lineinfile cannot express a multi-line value, so this
    # branches to copy, whose idempotency is content-based rather than regexp-based. #91.
    $isBanner = $line -match "`n"

    $body = if ($isBanner) {
        [ordered] @{
            'ansible.builtin.copy' = [ordered] @{
                'dest' = $Rule.FilePath
                'content' = $line
            }
            'become' = $true
        }
    }
    else {
        $lineinfile = [ordered] @{
            'path' = $Rule.FilePath
            'line' = $line
        }
        if ($regexp) { $lineinfile.regexp = $regexp }

        [ordered] @{
            'ansible.builtin.lineinfile' = $lineinfile
            'become' = $true
        }
    }

    $detail = if ($isBanner) {
        'Ensure {0} contains the required banner text' -f $leaf
    }
    else {
        'Ensure {0} contains "{1}"' -f $leaf, $line
    }

    @{
        # Sub-rules of one requirement often touch more than one file - Group-AnsibleTask's
        # caller joins every distinct leaf seen across the group, in the order they appear.
        GroupDetail = $leaf
        Task = @(
            @{
                Detail = $detail
                Body = $body
            }
        )
    }
}

<#
.SYNOPSIS
    Why a rule's data cannot become a working lineinfile task, or $null when it can.
.DESCRIPTION
    Four conditions, all reading the rule alone - see ADR 0009:

      - FilePath ends in '/': a PowerStig parse failure manufactured a directory, not a file (#81)
      - DoesNotContainPattern fails to compile: PowerStig could not have meant it either (#89)
      - ContainsLine carries a non-ASCII character: defeats lineinfile's literal fallback (#90)
      - Id is one of the 35 rules #88 found carry check-text prose instead of a line

    The 35 are an explicit, hand-maintained list rather than a keyword predicate re-run at
    generation time - #88's own research found its scan not proven free of false positives
    against future STIG revisions. Re-verify against the current data whenever the map's Notes
    say to re-pull upstream.
#>
function Get-AnsibleNxFileLineSkipReason {
    param ($Rule)

    if ($Rule.FilePath -match '/$') { return 'FilePath is a directory, not a file' }

    if ($Rule.DoesNotContainPattern) {
        try { [regex]::new($Rule.DoesNotContainPattern) | Out-Null }
        catch { return 'DoesNotContainPattern does not compile as a regular expression' }
    }

    if ($Rule.ContainsLine -match '[^\x00-\x7F]') { return 'ContainsLine carries a non-ASCII character' }

    # RHEL-9-2.8 (12), OracleLinux-8-2.4 (12), OracleLinux-9-1.1 (11) - verified against the
    # processed STIG XML 2026-09-20. V-257779 matches the same keyword scan but is excluded: its
    # ContainsLine is the legitimate DoD login banner, handled by the copy branch instead.
    $proseRuleId = @(
        'V-248535', 'V-248670.a', 'V-248670.b', 'V-248670.c', 'V-248670.d', 'V-248670.e'
        'V-248723.b', 'V-248723.c', 'V-248733.b', 'V-248733.c', 'V-248816', 'V-248843.a'
        'V-258080.b', 'V-258084', 'V-258133.b', 'V-258133.c', 'V-258149', 'V-258165.a'
        'V-258165.c', 'V-258165.d', 'V-258166.b', 'V-258166.c', 'V-258167.b', 'V-258167.c'
        'V-271583.b', 'V-271583.d', 'V-271583.e', 'V-271584.b', 'V-271584.c', 'V-271585.b'
        'V-271585.c', 'V-271594.a', 'V-271609.b', 'V-271609.c', 'V-271722'
    )
    if ($proseRuleId -contains $Rule.Id) { return 'ContainsLine is STIG check-text prose, not a line to write' }

    $null
}
