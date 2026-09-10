function New-AnsiblePlaybook {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName,

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [string] $OutputPath,

        [Parameter()]
        [string] $RoleName
    )

    if ([string]::IsNullOrWhiteSpace($RoleName)) {
        $RoleName = $StigName.ToLower() -replace '[^\w]+', '_'
    }

    $resolvedOutputPath = Resolve-AnsibleOutputPath -Path $OutputPath
    $variablePrefix = Get-AnsibleVariablePrefix -StigName $StigName
    $role = New-AnsibleRoleScaffold -Path $resolvedOutputPath -RoleName $RoleName -VariablePrefix $variablePrefix

    [xml] $xml = Get-Content (Get-PowerStigFile -Type Name -Path $Path | Where-Object BaseName -like $StigName*)

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
    $rules | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $stigId |
        Export-AnsibleTaskBySeverity -OutputPath $role.TaskPath
    $rules | Export-AnsibleConditionalValue -StigName $StigName -OutputPath $role.DefaultPath

    $ruleNames.Where({ $_ -notmatch 'RootCertificate|Service' }).Foreach({
        [pscustomobject] @{
            PowerStigRule = $_
            StigRule = $xml.DISASTIG.$_.Rule | Where-Object { $_.OrganizationValueRequired -eq $true }
        }
    }) | Export-AnsibleOrganizationValue -StigName $StigName -Path $Path -OutputPath $role.DefaultPath

    $role
}
