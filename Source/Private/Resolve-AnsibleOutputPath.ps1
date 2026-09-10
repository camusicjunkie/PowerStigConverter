function Resolve-AnsibleOutputPath {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $Path
    )

    $outputPath = if ([string]::IsNullOrWhiteSpace($Path)) {
        $PWD.ProviderPath
    }
    else {
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    if (-not (Test-Path -Path $outputPath)) {
        $null = New-Item -Path $outputPath -ItemType Directory -Force
    }

    $outputPath
}
