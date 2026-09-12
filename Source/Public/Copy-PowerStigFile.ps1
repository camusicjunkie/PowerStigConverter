function Copy-PowerStigFile {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $Path
    )

    $repoPath = Resolve-PowerStigPath -Path $Path

    # Each step depends on the one before it, so they are run one at a time and checked. git
    # reports trouble by exit code rather than by throwing; without the check a failed clone is
    # followed by two commands against a repository that is not there, and the fetch looks to
    # have worked until New-AnsiblePlaybook finds no STIG data at the path.
    $steps = @(
        @{
            Description = 'clone the PowerStig repository'
            Arguments = @('clone', '--no-checkout', 'https://github.com/microsoft/PowerStig.git', $repoPath)
        }
        @{
            Description = 'limit the checkout to the processed STIG data'
            Arguments = @('-C', $repoPath, 'sparse-checkout', 'set', '--no-cone', 'source/StigData/Processed')
        }
        @{
            Description = 'check the processed STIG data out of the dev branch'
            Arguments = @('-C', $repoPath, 'checkout', 'origin/dev', '--', 'source/StigData/Processed')
        }
    )

    try {
        $null = Get-Command -Name git -ErrorAction Stop

        foreach ($step in $steps) {
            # Cleared first so an exit code the caller left behind cannot read as this step
            # failing; git sets it either way.
            $global:LASTEXITCODE = 0

            $arguments = $step.Arguments
            git @arguments

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not $($step.Description): git exited with $LASTEXITCODE. Nothing was fetched into $repoPath. If it already holds a clone, delete it or fetch somewhere else."
                return
            }
        }
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        Write-Warning 'Git is not installed. It must be installed before the PowerStig files can be downloaded.'
    }
}
