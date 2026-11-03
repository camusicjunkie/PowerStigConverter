function Get-StigNameCompletion {
    <#
    .SYNOPSIS
        The STIG names New-AnsiblePlaybook's -StigName completes to.
    .DESCRIPTION
        Registered as the argument completer in prefix.ps1. Names are offered without the
        revision, because -StigName is matched exactly against them. See #237.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'PowerShell passes a completer all five; only the word being completed is used')]
    [OutputType([System.Management.Automation.CompletionResult])]
    param (
        # The command being completed
        $CommandName,

        # The parameter being completed
        $ParameterName,

        # What has been typed so far
        [string] $WordToComplete,

        # The command's syntax tree
        $CommandAst,

        # The parameters already bound
        $FakeBoundParameters
    )

    $stigNames = (Get-PowerStigFile -Type Name).BaseName -replace '-[\d.]+$' | Sort-Object -Unique
    $stigNames | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
