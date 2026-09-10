function New-AnsiblePlaybook {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    [xml] $xml = Get-Content (Get-PowerStigFile -Type Name | Where-Object BaseName -like $StigName*)

    $stigId = $xml.DISASTIG.stigid

    $ruleNames = $xml.DISASTIG.psobject.Properties.Name -like '*Rule'
    $rules = $ruleNames.Where({ $_ -notmatch 'Document|Manual' }).Foreach({
        $dscResourceModule = $xml.DISASTIG.$_.dscresourcemodule
        [pscustomobject] @{
            DscResourceModule = $dscResourceModule
            PowerStigRule = $_
            StigRule = $xml.DISASTIG.$_.Rule
        }
    })
    $rules | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $stigId | Export-AnsibleTaskBySeverity
    $rules | Export-AnsibleConditionalValue -StigName $StigName

    $ruleNames.Where({ $_ -notmatch 'RootCertificate|Service' }).Foreach({
        [pscustomobject] @{
            PowerStigRule = $_
            StigRule = $xml.DISASTIG.$_.Rule | Where-Object { $_.OrganizationValueRequired -eq $true }
        }
    }) | Export-AnsibleOrganizationValue -StigName $StigName
}
