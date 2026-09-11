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
        [string] $RoleName,

        # Generate the role even though the org settings file leaves values for the organization
        # to decide still unanswered. Those values are emitted blank; see docs/adr/0001.
        [Parameter()]
        [switch] $AllowIncompleteOrganizationValue
    )

    if ([string]::IsNullOrWhiteSpace($RoleName)) {
        $RoleName = $StigName.ToLower() -replace '[^\w]+', '_'
    }

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

    # Read the org settings once and hand the same map to the check, the generators and the
    # exporter. It used to be re-read and re-parsed once per rule from two places, which left
    # nowhere to judge the inputs complete before writing anything.
    $orgSetting = Get-PowerStigOrgSetting -StigName $StigName -Path $Path

    # A value DISA leaves to the adopting organization is an outstanding decision, not a data
    # error. Refuse to write a role that would silently set an empty value, and do it before
    # New-AnsibleRoleScaffold puts anything on disk, so a refused conversion leaves no trace.
    $gaps = @(foreach ($ruleGroup in $rules) {
        $ruleType = $ruleGroup.PowerStigRule -replace 'Rule'
        if (-not $script:organizationData.ContainsKey($ruleType)) { continue }

        foreach ($rule in $ruleGroup.StigRule) {
            Get-AnsibleOrganizationValueGap -Rule $rule -RuleType $ruleType -OrgSetting $orgSetting
        }
    })

    if ($gaps.Count -gt 0) {
        $message = Format-AnsibleOrganizationValueGap -Gap $gaps -StigName $StigName

        if (-not $AllowIncompleteOrganizationValue) {
            $exception = [System.InvalidOperationException]::new($message)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception,
                'IncompleteOrganizationValue',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $gaps
            ))
        }

        Write-Warning $message
    }

    $resolvedOutputPath = Resolve-AnsibleOutputPath -Path $OutputPath
    $role = New-AnsibleRoleScaffold -Path $resolvedOutputPath -RoleName $RoleName -StigName $StigName

    # Convert once and feed both exporters from the same tasks. Deriving the conditional
    # toggles from the generated tasks rather than from the rule list is what keeps the two in
    # step: rules the generators skip - duplicates, and rule types with no generator - produce
    # no task, and so can no longer leave a toggle behind in defaults/ that guards nothing.
    $tasks = $rules | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $stigId -OrgSetting $orgSetting

    $tasks | Export-AnsibleTaskBySeverity -OutputPath $role.TaskPath
    $tasks | Export-AnsibleConditionalValue -StigName $StigName -OutputPath $role.DefaultPath

    $ruleNames.Where({ $_ -notmatch 'RootCertificate|Service' }).Foreach({
        [pscustomobject] @{
            PowerStigRule = $_
            StigRule = $xml.DISASTIG.$_.Rule | Where-Object { $_.OrganizationValueRequired -eq $true }
        }
    }) | Export-AnsibleOrganizationValue -StigName $StigName -OrgSetting $orgSetting -OutputPath $role.DefaultPath

    $role
}
