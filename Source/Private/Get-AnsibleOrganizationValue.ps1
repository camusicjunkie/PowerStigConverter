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

        # A value the organization decides never reaches the task as a literal. It is declared
        # in defaults/ and the task interpolates it, so the operator can answer the question by
        # editing one file instead of regenerating the role - and so an assert can check at run
        # time that it was answered at all. See docs/adr/0003.
        $reference = {
            param ([string] $Field)
            '{0} {1} {2}' -f '{{', (Get-AnsibleOrganizationVariableName -Rule $Rule -RuleType $RuleType -Field $Field -StigName $StigName), '}}'
        }

        if ($RuleType -eq 'Service') {
            [pscustomobject] @{
                ServiceName = & $reference 'ServiceName'
                StartupType = & $reference 'StartupType'
            }
        }
        elseif ($RuleType -eq 'IisLogging') {
            [pscustomobject] @{
                LogFlags = & $reference 'LogFlags'
                LogFormat = & $reference 'LogFormat'
                LogPeriod = & $reference 'LogPeriod'
                LogTarget = & $reference 'LogTargetW3C'
                # LogCustomFields is a nested structure rather than a scalar, and it is the one
                # field marked optional, so nothing asserts on it and it stays built in place.
                LogCustomFields = $OrgSetting[$Rule.Id].LogCustomFieldEntry
            }
        }
        else { & $reference $orgValue }
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
                LogFlags = if ($rule.LogFlags) { , ($rule.LogFlags -split ',') }
                LogFormat = $rule.LogFormat
                LogPeriod = $rule.LogPeriod
                LogTarget = if ($rule.LogTargetW3C) { , ($rule.LogTargetW3C -split ',') }
                LogCustomFields = $rule.LogCustomFieldEntry
            }
        }
        # A field the task needs as a list is split here rather than in the generator, so that
        # both halves of this function hand back the same shape.
        elseif ($script:organizationData[$RuleType]['List'] -contains $orgValue) {
            , ($Rule.$orgValue -split ',')
        }
        else { $Rule.$orgValue }
    }
}
