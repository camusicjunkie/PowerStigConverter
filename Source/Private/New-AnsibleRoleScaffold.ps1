function New-AnsibleRoleScaffold {
    [CmdletBinding()]
    param (
        # Directory the role directory is created under.
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $RoleName
    )

    $rolePath = Join-Path $Path $RoleName

    # Scaffold only when the role is not already there. The plaster template writes the
    # hand-editable files (tasks/main.yml, defaults/main/main.yml, vars, handlers), so
    # re-running it over an existing role would discard whatever the user changed. The
    # generated files are written separately and are always replaced.
    if (-not (Test-Path -Path $rolePath)) {
        $null = Invoke-Plaster -TemplatePath (Join-Path $PSScriptRoot 'Roles') -DestinationPath $Path -RoleName $RoleName -NoLogo -Force
    }

    $taskPath = Join-Path $rolePath 'tasks'
    $defaultPath = Join-Path $rolePath 'defaults' | Join-Path -ChildPath 'main'

    foreach ($required in $taskPath, $defaultPath) {
        if (-not (Test-Path -Path $required)) {
            $null = New-Item -Path $required -ItemType Directory -Force
        }
    }

    [pscustomobject] @{
        Path = $rolePath
        TaskPath = $taskPath
        DefaultPath = $defaultPath
    }
}
