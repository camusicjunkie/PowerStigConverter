function Get-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        # The PowerStig rule type this value belongs to. Must be a key of OrganizationData.psd1,
        # which supplies the rule and org node property names to read for that type.
        [Parameter(Mandatory)]
        [ValidateSet('AccountPolicy', 'IisLogging', 'Registry', 'RootCertificate', 'SecurityOption', 'Service', 'UserRight')]
        [string] $RuleType,

        [string] $StigName,

        # The org settings loaded once by Get-PowerStigOrgSetting, keyed by rule id.
        [hashtable] $OrgSetting = @{}
    )

    $orgName = $script:organizationData[$RuleType]['Name']
    $orgValue = $script:organizationData[$RuleType]['Value']

    if ($Rule.OrganizationValueRequired -eq $true) {

        $node = $OrgSetting[$Rule.Id]

        # New-AnsiblePlaybook has already reported every missing and unanswered setting - it
        # either refused to generate the role or the caller asked for blanks explicitly - so
        # there is nothing left to warn about here.
        if ([string]::IsNullOrWhiteSpace($node.$orgValue)) { return }

        $navParams = @{
            TaskId = $Rule.Id
            TaskName = $Rule.$orgName
            StigName = $StigName
        }
        if ($RuleType -eq 'RootCertificate') { $node.$orgValue }
        elseif ($RuleType -eq 'Service') {
            [pscustomobject] @{
                ServiceName = $node.ServiceName
                StartupType = $node.StartupType
            }
        }
        elseif ($RuleType -eq 'IisLogging') {
            [pscustomobject] @{
                LogFlags = $node.LogFlags
                LogFormat = $node.LogFormat
                LogPeriod = $node.LogPeriod
                LogTarget = $node.LogTargetW3C
                LogCustomFields = $node.LogCustomFieldEntry
            }
        }
        else { New-AnsibleVariable @navParams -Type Organization }
    }
    else {

        if ($Rule.$orgValue -match 'Enabled|Disabled') {
            $data = $script:accountPolicyData + $script:securityOptionData
            $attributeName = $Rule.$orgName -replace '/|\s', '_' -replace ':'
            # The Option table is keyed by the value the rule asks for - Enabled, Disabled -
            # so it has to be indexed by that value, not by the name of the property the value
            # was read from. Indexing by the property name misses every time, and [int] $null
            # then turns every one of these rules into 0.
            [int] $data[$attributeName]['Option'][$Rule.$orgValue]
        }
        elseif ($orgValue -eq 'Identity' -and $rule.$orgValue -eq 'NULL') { @() }
        elseif ($RuleType -eq 'Service') {
            [pscustomobject] @{
                ServiceName = $rule.ServiceName
                StartupType = $rule.StartupType
            }
        }
        elseif ($RuleType -eq 'IisLogging') {
            [pscustomobject] @{
                LogFlags = $rule.LogFlags
                LogFormat = $rule.LogFormat
                LogPeriod = $rule.LogPeriod
                LogTarget = $rule.LogTargetW3C
                LogCustomFields = $rule.LogCustomFieldEntry
            }
        }
        else { $Rule.$orgValue }
    }
}
