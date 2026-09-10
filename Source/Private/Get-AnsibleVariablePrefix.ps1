function Get-AnsibleVariablePrefix {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    # WindowsServer-2022-MS -> stig_server_2022. Every variable the role uses is named from
    # this prefix, so the scaffolding and the generated files must derive it the same way.
    $stig = $StigName.ToLower() -replace '^Windows(\w+)-(\d+).*$', '$1_$2'

    'stig_{0}' -f $stig
}
