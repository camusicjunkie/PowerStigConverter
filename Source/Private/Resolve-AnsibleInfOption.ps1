function Resolve-AnsibleInfOption {
    <#
    .SYNOPSIS
        The INF section, key and mapped value one AccountPolicy or SecurityOption option resolves to.
    .DESCRIPTION
        AccountPolicyData.psd1 and SecurityOptionData.psd1 index the same shape by a mangled
        version of the option name (slashes and whitespace to underscore, colons dropped). This is
        the one place that mangling happens and the one place both files are read, so a task
        generator and Resolve-AnsibleOrganizationValue can each ask it instead of keeping their
        own copy.
    .OUTPUTS
        A single object carrying Section, Key and Value. Value is the entry's Option mapped for
        whatever -Value was asked for - a Registry Values entry keeps it a string, since '4,1' cast
        to [int] reads the comma as a thousands separator and yields 41; every other section's
        entry is [int]. Value is $null when -Value was not passed.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $OptionName,

        [string] $Value
    )

    $option = $script:accountPolicyData + $script:securityOptionData
    $key = $OptionName -replace '/|\s', '_' -replace ':'
    $entry = $option[$key]

    # Keyed by the value asked for, not the property name - indexing by the name misses every
    # time and the cast then turns every rule into 0.
    $mappedValue = if ($PSBoundParameters.ContainsKey('Value')) {
        $mapped = $entry['Option'][$Value]
        if ($entry['Section'] -eq 'Registry Values') { $mapped } else { [int] $mapped }
    }

    [pscustomobject] @{
        Section = $entry['Section']
        Key = $entry['Value']
        Value = $mappedValue
    }
}
