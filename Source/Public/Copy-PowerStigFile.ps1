function Copy-PowerStigFile {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $Path
    )

    # TODO: Create error handling for path Parameter. Also allow for relative paths.
    $repoPath = "$env:LOCALAPPDATA\PowerStig"

    try {
        Get-Command -Name git -ErrorAction Stop
        git clone --no-checkout https://github.com/microsoft/PowerStig.git $repoPath
        git -C $repoPath sparse-checkout set --no-cone source/StigData/Processed
        git -C $repoPath checkout origin/dev -- source/StigData/Processed
    }
    catch {
        Write-Warning 'Git is not installed. It must be installed before the PowerStig files can be downloaded.'
    }
}
