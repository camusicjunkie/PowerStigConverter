function Export-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Rule,

        [string] $StigName,

        [Parameter()]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    begin {
        $organization = [System.Collections.SortedList]::new()
    }
    process {
        # TODO: Consolidate code from Get-AnsibleOrganizationValue and below to a new function.
        $ruleName = $Rule.PowerStigRule -replace 'Rule'
        foreach ($rule in $Rule.StigRule) {

            [xml] $xmlOrg = Get-Content (Get-PowerStigFile -Type Org -Path $Path | Where-Object BaseName -like $StigName*)
            $node = (Select-Xml -Xml $xmlOrg -XPath "//OrganizationalSetting[@id = '$($rule.id)']").Node

            $taskName = if ($ruleName -eq 'IisLogging') { 'logpath' } else { $rule.($organizationData[$ruleName]['Name']) }
            $nodeValue = if ($ruleName -eq 'IisLogging') { $null } else { $node.($organizationData[$ruleName]['Value']) }

            $navParams = @{
                TaskId = $rule.id
                TaskName = $taskName
                NodeValue = $nodeValue
                StigName = $StigName
            }
            $organizationVariable = New-AnsibleVariable @navParams -Type OrganizationValue
            $organization.Add($rule.Id, $organizationVariable)
        }
    }
    end {
        $orgFile = Join-Path $OutputPath 'main_default_org.yml'

        $header = @'
{0}_cat1: true
{0}_cat2: true
{0}_cat3: true

'@ -f (New-AnsibleVariable -StigName $StigName -Type OrganizationValueGroup)

        $header | Set-Content -Path $orgFile -Encoding utf8

        if ($organization.Count -gt 0) {
            $organization.Values | Add-Content -Path $orgFile -Encoding utf8
        }
    }
}
