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
        [pscustomobject] @{
            PowerStigRule = $_
            StigRule = $xml.DISASTIG.$_.Rule
        }
    })

    # Read the org settings once and hand the same map to the check, the generators and the
    # exporter. It used to be re-read and re-parsed once per rule from two places, which left
    # nowhere to judge the inputs complete before writing anything.
    $organizationalSetting = Get-PowerStigOrgSetting -StigName $StigName -Path $Path

    # Convert first and feed the gate and every exporter from the same tasks, so only a rule that
    # produced a task can refuse or declare anything. Converting writes nothing. See docs/adr/0016.
    $tasks = @($rules | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $stigId -OrganizationalSetting $organizationalSetting)

    # A value DISA leaves to the adopting organization is an outstanding decision, not a data
    # error. Refuse to write a role that would silently set an empty value, and do it before
    # New-AnsibleRoleScaffold puts anything on disk, so a refused conversion leaves no trace.
    $incomplete = @($tasks.Incomplete | Where-Object { $_ })

    if ($incomplete.Count -gt 0) {
        $message = Format-AnsibleIncompleteOrganizationValue -Variable $incomplete -StigName $StigName

        if (-not $AllowIncompleteOrganizationValue) {
            $exception = [System.InvalidOperationException]::new($message)
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $exception,
                'IncompleteOrganizationValue',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $incomplete
            ))
        }

        Write-Warning $message
    }

    $resolvedOutputPath = Resolve-AnsibleOutputPath -Path $OutputPath
    $role = New-AnsibleRoleScaffold -Path $resolvedOutputPath -RoleName $RoleName -StigName $StigName

    # The exporters decide what the role declares; writing it is this function's job, so a test
    # can read their answer without a filesystem. See #19.
    Save-AnsibleRoleFile -OutputPath $role.TaskPath -Content ($tasks | Export-AnsibleTaskBySeverity -StigName $StigName)
    Save-AnsibleRoleFile -OutputPath $role.DefaultPath -Content ($tasks | Export-AnsibleConditionalValue -StigName $StigName)
    Save-AnsibleRoleFile -OutputPath $role.DefaultPath -Content ($tasks | Export-AnsibleOrganizationValue -StigName $StigName)

    Save-AnsibleRoleFile -OutputPath $role.HandlerPath -Content ($tasks | Export-AnsibleHandler)

    # The scaffolding writes handlers/main.yml once and never again, so a role scaffolded before
    # the handler channel existed has no import of the generated file and would run none of it.
    $handlerMain = Join-Path $role.HandlerPath 'main.yml'
    if ((Test-Path -Path $handlerMain) -and (Get-Content -Path $handlerMain -Raw) -notlike '*generated.yml*') {
        Write-Warning ('{0} does not import generated.yml, so the generated handlers will never run. Add an "ansible.builtin.import_tasks: generated.yml" entry to it.' -f $handlerMain)
    }

    $role
}
