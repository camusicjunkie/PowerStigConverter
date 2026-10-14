function New-AnsibleRoleScaffold {
    [CmdletBinding()]
    param (
        # Directory the role directory is created under.
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $RoleName,

        # The scaffolding names variables and asserts the target OS from this, so it must be
        # the same STIG the generated files are built from.
        [Parameter(Mandatory)]
        [string] $StigName
    )

    $rolePath = Join-Path $Path $RoleName

    # Scaffold only when the role is not already there. The plaster template writes the
    # hand-editable files (tasks/main.yml, defaults/main/main.yml, vars, handlers), so
    # re-running it over an existing role would discard whatever the user changed. The
    # generated files are written separately and are always replaced.
    if (-not (Test-Path -Path $rolePath)) {
        $osAssertion = Get-AnsibleOsAssertion -StigName $StigName

        $plasterParams = @{
            TemplatePath = Join-Path $PSScriptRoot 'Roles'
            DestinationPath = $Path
            RoleName = $RoleName
            VariablePrefix = Get-AnsibleVariablePrefix -StigName $StigName
            OsPattern = $osAssertion.Pattern
            OsDescription = $osAssertion.Description
            OsFamily = $osAssertion.OsFamily
            OsMajorVersion = if ($osAssertion.OsMajorVersion) { $osAssertion.OsMajorVersion } else { '' }
            NoLogo = $true
            Force = $true
        }

        $null = Invoke-Plaster @plasterParams
    }
    else {
        Add-AnsibleEnvFact -Path (Join-Path $rolePath 'tasks/main.yml') -StigName $StigName
    }

    $taskPath = Join-Path $rolePath 'tasks'
    $defaultPath = Join-Path $rolePath 'defaults' | Join-Path -ChildPath 'main'
    $handlerPath = Join-Path $rolePath 'handlers'

    foreach ($required in $taskPath, $defaultPath, $handlerPath) {
        if (-not (Test-Path -Path $required)) {
            $null = New-Item -Path $required -ItemType Directory -Force
        }
    }

    [pscustomobject] @{
        Path = $rolePath
        TaskPath = $taskPath
        DefaultPath = $defaultPath
        HandlerPath = $handlerPath
    }
}

function Add-AnsibleEnvFact {
    <#
    .SYNOPSIS
        Adds the env fact to a Windows role's tasks/main.yml when it lacks one.
    .DESCRIPTION
        tasks/main.yml is hand-editable and written once, so a role scaffolded before the env fact
        existed never gets it from the template. The task is copied from the template so the two
        cannot drift, and inserted ahead of the CAT imports. See #149 and docs/adr/0017.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    if (-not (Test-Path -Path $Path -PathType Leaf) -or
        (Get-AnsibleOsAssertion -StigName $StigName).OsFamily -ne 'Windows') {
        return
    }

    $prefix = Get-AnsibleVariablePrefix -StigName $StigName
    $content = Get-Content -Path $Path -Raw
    if ($content -match ('(?m)^\s*{0}_env\s*:' -f [regex]::Escape($prefix))) {
        return
    }

    $template = Get-Content -Path (Join-Path $PSScriptRoot 'Roles/main_task.yml') -Raw
    $block = [regex]::Match($template, "(?ms)(^#[^\r\n]*\r?\n)?^- name: Index the target's environment.*?^  tags: always\r?\n\r?\n")
    if (-not $block.Success) {
        return
    }

    $task = $block.Value.Replace('<%= $PLASTER_PARAM_VariablePrefix %>', $prefix)
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $task = $task -replace '\r?\n', $newline

    $anchor = [regex]::Match($content, '(?m)^- name: Execute the CAT 1 tasks')
    $updated = if ($anchor.Success) {
        $content.Insert($anchor.Index, $task)
    }
    else {
        $content.TrimEnd() + $newline + $newline + $task.TrimEnd() + $newline
    }

    Set-Content -Path $Path -Value $updated -NoNewline
}
