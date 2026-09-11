function Get-PowerStigOrgSetting {
    <#
    .SYNOPSIS
        Loads a STIG's org settings file into a map of rule id to OrganizationalSetting node.
    .DESCRIPTION
        The org settings file used to be re-read and re-parsed once per rule, from two places.
        Loading it once up front gives the conversion a single point at which the inputs can be
        judged complete, and lets every caller look a rule up by id instead of running its own
        XPath query.

        Returns an empty map when the file carries no settings; a rule with no entry is a
        missing setting, which Get-AnsibleOrganizationValueGap reports separately from one that
        is present but unanswered.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $StigName,

        [string] $Path
    )

    $orgFile = Get-PowerStigFile -Type Org -Path $Path | Where-Object BaseName -like "$StigName*"

    if ($null -eq $orgFile) {
        throw "No organization settings file was found for '$StigName'. PowerStig ships one '*.org.default.xml' beside each processed STIG."
    }

    [xml] $xmlOrg = Get-Content -Path $orgFile

    $settings = @{}
    foreach ($node in $xmlOrg.OrganizationalSettings.OrganizationalSetting) {
        if ($null -eq $node) { continue }
        $settings[$node.id] = $node
    }

    $settings
}
