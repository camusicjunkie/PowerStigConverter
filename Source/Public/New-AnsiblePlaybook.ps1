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
        $RoleName = Get-AnsibleRoleName -StigName $StigName
    }

    # The STIG's rules, already corrected and grouped by type, and its org settings, read once
    # and handed to the check, the generators and the exporter alike. See docs/adr/0002 and 0020.
    $stig = Import-PowerStigData -StigName $StigName -Path $Path

    # Convert first and feed the gate and every exporter from the same tasks, so only a rule that
    # produced a task can refuse or declare anything. Converting writes nothing. See docs/adr/0016.
    $tasks = @($stig.Rules | ConvertTo-AnsiblePlaybook -StigName $StigName -StigId $stig.StigId -OrganizationalSetting $stig.OrganizationalSetting)

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

    # tasks/main.yml is written once too, so a role scaffolded before #196 tests its severity
    # toggles bare, and -e <toggle>=false fails there on ansible-core 2.19+ instead of skipping.
    $taskMain = Join-Path $role.TaskPath 'main.yml'
    $bareToggle = '(?m)^\s*when:\s*{0}_cat[123]\s*$' -f [regex]::Escape((Get-AnsibleVariablePrefix -StigName $StigName))
    if ((Test-Path -Path $taskMain) -and (Get-Content -Path $taskMain -Raw) -match $bareToggle) {
        Write-Warning ('{0} tests its severity toggles without "| bool", so -e <toggle>=false fails on ansible-core 2.19+ instead of skipping. Add "| bool" to each "when:" on the CAT imports.' -f $taskMain)
    }

    $role
}
