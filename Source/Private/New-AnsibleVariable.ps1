function New-AnsibleVariable {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $TaskId,

        [Parameter()]
        [string] $TaskName,

        [Parameter()]
        [object] $NodeValue,

        [Parameter(Mandatory)]
        [ValidateSet('Conditional', 'ConditionalValue', 'Organization', 'OrganizationValue', 'OrganizationValueGroup')]
        [string] $Type,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    # Sub-rule ids carry a suffix (V-254343.b) that is not legal in an ansible variable name.
    $id = $TaskId -replace 'V-' -replace '[^A-Za-z0-9]+', '_'
    $name = $TaskName.ToLower() -replace '\s', '_' -replace '[^\w]+'
    $base = Get-AnsibleVariablePrefix -StigName $StigName

    # Org values are STIG text, and some of them (the DoD legal notice above all) contain a
    # colon followed by a space, which yaml reads as a nested mapping and which would make the
    # defaults file unparseable. Quote anything that cannot stand as a plain scalar, and leave
    # everything else alone so numbers keep being numbers.
    $quotedNodeValue = if ($NodeValue -is [string] -and $NodeValue -match ':\s|^\s|\s$|^[#&*!|>%@`]') {
        "'{0}'" -f ($NodeValue -replace "'", "''")
    }
    else {
        $NodeValue
    }

    switch ($Type) {
        'Conditional' { '{0}_{1}_when' -f $base, $id; break }
        'ConditionalValue' { '{0}_{1}_when: true' -f $base, $id; break }
        'Organization' { '{0} {1}_{2}_{3} {4}' -f '{{', $base, $id, $name, '}}'; break }
        'OrganizationValue' { "{0}_{1}_{2}: {3}" -f $base, $id, $name, $quotedNodeValue; break }
        'OrganizationValueGroup' { "{0}" -f $base; break }
    }
}
