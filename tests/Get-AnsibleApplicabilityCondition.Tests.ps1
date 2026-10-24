#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $processed = Join-Path $env:LOCALAPPDATA 'PowerStig/source/StigData/Processed'
    $script:stigFiles = @(Get-ChildItem $processed -Filter *.xml -ErrorAction SilentlyContinue |
        Where-Object Name -notlike '*.org.default.xml' |
        ForEach-Object { @{ StigFile = $_.BaseName; Path = $_.FullName } })
    # Pester refuses an empty -ForEach; one placeholder reports the data as missing instead.
    if ($stigFiles.Count -eq 0) { $script:stigFiles = @(@{ StigFile = 'the local PowerStig data'; Path = $null }) }
}

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $generators = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) 'Source/Private/Task') -Filter 'Build-Ansible*Task.ps1'
    $script:convertedType = @($generators | ForEach-Object { ($_.BaseName -replace '^Build-Ansible' -replace 'Task$') + 'Rule' })
}

# The off-domain wording is read from prose, so a phrasing DISA has not used before must fail here
# rather than leave its rule applied on a workgroup host. See docs/adr/0026.
Describe 'Get-AnsibleApplicabilityCondition' {

    # A line naming NA beside a domain either marks the rule NA off a domain, or splits domain
    # controllers from member servers, which the separate DC and MS STIGs already do. Only
    # checkable where PowerStig's data has been fetched; dispatch's tests cover the wording itself.
    It 'classifies every NA-by-domain line of <StigFile>' -ForEach $stigFiles {
        if (-not $Path) { Set-ItResult -Skipped -Because 'PowerStig''s data has not been fetched'; return }

        [xml] $xml = Get-Content $Path -Raw
        $dcSplit = '(NA|not applicable) for (domain controllers|other systems|member servers)'

        $unclassified = foreach ($type in $xml.DISASTIG.ChildNodes) {
            if ($convertedType -notcontains $type.LocalName) { continue }
            foreach ($rule in $type.Rule) {
                if ($rule.DuplicateOf) { continue }
                foreach ($line in (([string] $rule.RawString) -split '\r?\n')) {
                    if ($line -notmatch '\b(NA|not applicable)\b' -or $line -notmatch 'domain') { continue }

                    $condition = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Line = $line } {
                        param ($Line)
                        Get-AnsibleApplicabilityCondition -Rule ([pscustomobject] @{ RawString = $Line })
                    }
                    if (-not $condition -and $line -notmatch $dcSplit) { '{0}: {1}' -f $rule.id, $line.Trim() }
                }
            }
        }

        $unclassified | Should-BeNull
    }
}
