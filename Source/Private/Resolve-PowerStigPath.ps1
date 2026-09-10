function Resolve-PowerStigPath {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return "$env:LOCALAPPDATA\PowerStig"
    }

    # The directory does not have to exist yet -- Copy-PowerStigFile creates it -- so a
    # relative path is resolved against the current location without requiring a target.
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
