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
            NoLogo = $true
            Force = $true
        }

        $null = Invoke-Plaster @plasterParams
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
