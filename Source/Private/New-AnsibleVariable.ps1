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

    $id = $TaskId -replace 'V-'
    $name = $TaskName.ToLower() -replace '\s', '_' -replace '[^\w]+'
    $base = Get-AnsibleVariablePrefix -StigName $StigName

    switch ($Type) {
        'Conditional' { '{0}_{1}_when' -f $base, $id; break }
        'ConditionalValue' { '{0}_{1}_when: true' -f $base, $id; break }
        'Organization' { '{0} {1}_{2}_{3} {4}' -f '{{', $base, $id, $name, '}}'; break }
        'OrganizationValue' { "{0}_{1}_{2}: {3}" -f $base, $id, $name, $NodeValue; break }
        'OrganizationValueGroup' { "{0}" -f $base; break }
    }
}
