function Import-PowerStigData {
    <#
    .SYNOPSIS
        Loads one STIG for conversion: its rules, repaired and grouped by rule type, and its org
        settings.
    .DESCRIPTION
        Finds the STIG by its exact STIG name, at its newest revision unless -Revision names one,
        and the org settings file of that same revision. Its corrections are applied
        (docs/adr/0020) before the rules are gathered by type, since a correction can change a
        rule's type, and Manual and Document rules are dropped only after that. The org settings
        are loaded first because a correction can add or change one.
    .OUTPUTS
        One object carrying StigName, StigFile (the processed file's base name, revision
        included), StigId, Profile (Get-PowerStigProfile's STIG profile), Rules (one entry per
        converted rule type, PowerStigRule and StigRule) and OrganizationalSetting (the org
        settings keyed by rule id).
    #>
    [CmdletBinding()]
    param (
        # The STIG name: the processed file's name without its revision, e.g. WindowsServer-2022-MS.
        [Parameter(Mandatory)]
        [string] $StigName,

        # A revision to load instead of the newest, e.g. 2.6.
        [string] $Revision,

        # Where Copy-PowerStigFile put the data, if not the default.
        [string] $Path,

        # Corrections keyed by processed file then rule id, as RuleCorrection.psd1 holds them.
        [hashtable] $Correction = $script:ruleCorrection
    )

    $processed = Join-Path (Resolve-PowerStigPath -Path $Path) 'source\StigData\Processed'

    $stigFile = if ($Revision) {
        Get-Item -LiteralPath (Join-Path $processed "$StigName-$Revision.xml") -ErrorAction Ignore
    }
    else {
        Get-PowerStigFile -Type Name -Path $Path | Where-Object { ($_.BaseName -replace '-[\d.]+$') -eq $StigName }
    }

    if ($null -eq $stigFile) {
        # Name the STIGs the caller may have meant, so a partial name says what it matched.
        $known = @(Get-PowerStigFile -Type Name -Path $Path | ForEach-Object { $_.BaseName -replace '-[\d.]+$' } | Sort-Object -Unique)
        $near = @($known | Where-Object { $_ -like "$StigName*" })
        $wanted = if ($Revision) { "'$StigName' at revision $Revision" } else { "'$StigName'" }
        $message = if ($near.Count) { 'No downloaded STIG is named {0}. Did you mean {1}?' -f $wanted, ($near -join ', ') }
            else { 'No downloaded STIG is named {0}. Copy-PowerStigFile downloads the STIG data; -Path says where it was put.' -f $wanted }

        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new($message),
            'StigNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $StigName
        ))
    }

    $orgFile = Join-Path $stigFile.DirectoryName ('{0}.org.default.xml' -f $stigFile.BaseName)
    if (-not (Test-Path -LiteralPath $orgFile)) {
        # The same failure style as the completeness check this feeds, so a caller traps both the
        # same way. See docs/adr/0002.
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.FileNotFoundException]::new(
                "No organization settings file was found for '$($stigFile.BaseName)'. PowerStig ships one '*.org.default.xml' beside each processed STIG."
            ),
            'OrgSettingsFileNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $StigName
        ))
    }

    [xml] $xml = Get-Content -LiteralPath $stigFile.FullName -Raw
    [xml] $org = Get-Content -LiteralPath $orgFile -Raw

    $settings = @{}
    foreach ($node in $org.OrganizationalSettings.OrganizationalSetting) {
        if ($null -ne $node) { $settings[$node.id] = $node }
    }

    Repair-PowerStigData -Xml $xml -OrganizationalSetting $settings -StigFile $stigFile.BaseName -Correction $Correction[$stigFile.BaseName]

    $ruleTypes = $xml.DISASTIG.psobject.Properties.Name -like '*Rule'
    $rules = @(foreach ($ruleType in $ruleTypes.Where({ $_ -notmatch 'Document|Manual' })) {
        [pscustomobject] @{
            PowerStigRule = $ruleType
            StigRule = $xml.DISASTIG.$ruleType.Rule
        }
    })

    [pscustomobject] @{
        StigName = $StigName
        StigFile = $stigFile.BaseName
        StigId = $xml.DISASTIG.stigid
        Profile = Get-PowerStigProfile -StigName $StigName -Revision ($stigFile.BaseName -replace '^.+-([\d.]+)$', '$1') -StigId $xml.DISASTIG.stigid
        Rules = $rules
        OrganizationalSetting = $settings
    }
}
