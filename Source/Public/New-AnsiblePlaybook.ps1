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
    $role = New-AnsibleRoleScaffold -Path $resolvedOutputPath -RoleName $RoleName -StigName $StigName

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
    # Convert once and feed both exporters from the same tasks. Deriving the conditional
    # toggles from the generated tasks rather than from the rule list is what keeps the two in
    # step: rules the generators skip - duplicates, and rule types with no generator - produce
    # no task, and so can no longer leave a toggle behind in defaults/ that guards nothing.
    $tasks = $rules | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $stigId -Path $Path

    $tasks | Export-AnsibleTaskBySeverity -OutputPath $role.TaskPath
    $tasks | Export-AnsibleConditionalValue -StigName $StigName -OutputPath $role.DefaultPath

    $ruleNames.Where({ $_ -notmatch 'RootCertificate|Service' }).Foreach({
        [pscustomobject] @{
            PowerStigRule = $_
            StigRule = $xml.DISASTIG.$_.Rule | Where-Object { $_.OrganizationValueRequired -eq $true }
        }
    }) | Export-AnsibleOrganizationValue -StigName $StigName -Path $Path -OutputPath $role.DefaultPath

    $role
}
