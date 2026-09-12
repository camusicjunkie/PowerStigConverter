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
        [ValidateSet('Conditional', 'ConditionalValue', 'Organization', 'OrganizationName', 'OrganizationValue', 'OrganizationValueGroup')]
        [string] $Type,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    # Sub-rule ids carry a suffix (V-254343.b) that is not legal in an ansible variable name.
    $id = $TaskId -replace 'V-' -replace '[^A-Za-z0-9]+', '_'
    $name = $TaskName.ToLower() -replace '\s', '_' -replace '[^\w]+'
    $base = Get-AnsibleVariablePrefix -StigName $StigName

    # The declaration in defaults/, the reference in tasks/ and the assert that guards it all
    # have to name the same variable, so they all build that name here.
    $organizationName = '{0}_{1}_{2}' -f $base, $id, $name

    # A value the task needs as a list is split before it gets here, and is written as a yaml
    # flow sequence so the whole variable can be interpolated as one. Splitting it on the host
    # instead would make the shape the module receives depend on a jinja expression no test can
    # see. See docs/adr/0003.
    $quotedNodeValue = if ($NodeValue -is [array]) {
        '[{0}]' -f (($NodeValue | ForEach-Object { Format-AnsibleYamlScalar -Value $_ -InSequence }) -join ', ')
    }
    else {
        Format-AnsibleYamlScalar -Value $NodeValue
    }

    switch ($Type) {
        'Conditional' { '{0}_{1}_when' -f $base, $id; break }
        'ConditionalValue' { '{0}_{1}_when: true' -f $base, $id; break }
        'Organization' { '{0} {1} {2}' -f '{{', $organizationName, '}}'; break }
        'OrganizationName' { $organizationName; break }
        'OrganizationValue' { '{0}: {1}' -f $organizationName, $quotedNodeValue; break }
        'OrganizationValueGroup' { "{0}" -f $base; break }
    }
}
