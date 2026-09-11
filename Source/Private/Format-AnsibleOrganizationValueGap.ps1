function Format-AnsibleOrganizationValueGap {
    <#
    .SYNOPSIS
        Renders organization value gaps as the message a human reads.
    .DESCRIPTION
        The gaps themselves travel on the terminating error's TargetObject so that tests and
        tooling assert on objects rather than on prose; this is only the human-readable half.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object[]] $Gap,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    $unanswered = @($Gap).Where({ $_.Reason -eq 'Unanswered' }).Count
    $missing = @($Gap).Where({ $_.Reason -eq 'Missing' }).Count

    $counts = @(
        if ($unanswered -gt 0) { '{0} unanswered' -f $unanswered }
        if ($missing -gt 0) { '{0} missing' -f $missing }
    ) -join ' and '

    $width = ($Gap.RuleId | Measure-Object -Property Length -Maximum).Maximum
    $lines = foreach ($item in $Gap) {
        $remedy = if ($item.Reason -eq 'Missing') {
            'no entry in the org settings file - it may not match this STIG version'
        }
        else {
            'left blank for the organization to decide'
        }
        '  {0}  {1,-15} {2}: {3}' -f $item.RuleId.PadRight($width), $item.RuleType, $item.Field, $remedy
    }

    @(
        "The organization settings for '$StigName' do not answer every value the role needs ($counts)."
        ''
        $lines
        ''
        'Answer these in the org settings file, or pass -AllowIncompleteOrganizationValue to'
        'generate the role with them blank and an assert guarding each one.'
    ) -join [System.Environment]::NewLine
}
