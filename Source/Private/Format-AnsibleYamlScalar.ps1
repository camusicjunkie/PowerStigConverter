function Format-AnsibleYamlScalar {
    <#
    .SYNOPSIS
        Quotes a value for defaults/ only when yaml would otherwise misread it.
    .DESCRIPTION
        Org values are STIG text, and some of them (the DoD legal notice above all) contain a
        colon followed by a space, which yaml reads as a nested mapping and which would make the
        defaults file unparseable. Quote anything that cannot stand as a plain scalar, and leave
        everything else alone so numbers keep being numbers.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [object] $Value,

        # Inside a flow sequence a comma and a closing bracket end the element, so those need
        # quoting too; a plain scalar can hold both without any help.
        [switch] $InSequence
    )

    # Digits separated by colons are a sexagesimal integer in the yaml 1.1 ansible parses, so an
    # unquoted 00:05:00 reaches the module as 300 rather than as the timespan the STIG wrote.
    $sexagesimal = '|^-?\d+(:\d+)+$'

    $unsafe = if ($InSequence) { ':\s|^\s|\s$|,|]|^[#&*!|>%@`\[]' + $sexagesimal }
        else { ':\s|^\s|\s$|^[#&*!|>%@`\[\]]' + $sexagesimal }

    if ($Value -is [string] -and $Value -match $unsafe) {
        "'{0}'" -f ($Value -replace "'", "''")
    }
    else {
        $Value
    }
}
