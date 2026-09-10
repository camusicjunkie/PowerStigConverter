function Get-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        [string] $StigName
    )

    $ruleName = (Get-PSCallStack)[1].Command -replace 'New-Ansible|Task'
    $orgName = $script:organizationData[$ruleName]['Name']
    $orgValue = $script:organizationData[$ruleName]['Value']

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
        elseif ($ruleName -eq 'RootCertificate') { $node.$orgValue }
        elseif ($ruleName -eq 'Service') {
            [pscustomobject] @{
                ServiceName = $node.ServiceName
                StartupType = $node.StartupType
            }
        }
        elseif ($ruleName -eq 'IisLogging') {
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
        elseif ($ruleName -eq 'Service') {
            [pscustomobject] @{
                ServiceName = $rule.ServiceName
                StartupType = $rule.StartupType
            }
        }
        elseif ($ruleName -eq 'IisLogging') {
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
