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

        [string] $StigName
    )

    $orgName = $script:organizationData[$RuleType]['Name']
    $orgValue = $script:organizationData[$RuleType]['Value']

    if ($Rule.OrganizationValueRequired -eq $true) {

        [xml] $xmlOrg = Get-Content (Get-PowerStigFile -Type Org | Where-Object BaseName -like $StigName*)
        $node = (Select-Xml -Xml $xmlOrg -XPath "//OrganizationalSetting[@id = '$($Rule.id)']").Node

        # Validate the org settings file is filled out for this Id
        if (Test-PowerStigOrgValue -NodeValue $node.$orgValue -RuleId $Rule.Id) { return }

        $navParams = @{
            TaskId = $Rule.Id
            TaskName = $Rule.$orgName
            StigName = $StigName
        }
        if ($orgValue -eq 'Identity' -and $null -eq $node.$orgValue) { @() }
        elseif ($RuleType -eq 'RootCertificate') { $node.$orgValue }
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
            [int] $data[$attributeName]['Option'][$orgValue]
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
