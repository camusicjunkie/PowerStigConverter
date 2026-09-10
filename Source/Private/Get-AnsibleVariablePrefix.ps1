function Get-AnsibleVariablePrefix {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    # Every variable the role uses is named from this prefix, so the scaffolding and the
    # generated files must derive it the same way. Ansible variable names allow only letters,
    # digits and underscores, so nothing else may survive into the result.
    switch -Regex ($StigName) {
        # WindowsServer-2022-MS -> server_2022, WindowsServer-2012R2-DC -> server_2012r2,
        # WindowsClient-11 -> client_11. The release suffix is kept so that 2012R2 and a
        # hypothetical 2012 do not collapse onto the same prefix.
        '^Windows(\w+)-(\d+)(R\d)?' {
            $stig = '{0}_{1}{2}' -f $matches[1], $matches[2], $matches[3]
            break
        }
        # Application STIGs (IIS, SQL Server, .NET) keep their own name, sanitised.
        default {
            $stig = $StigName -replace '[^A-Za-z0-9]+', '_'
        }
    }

    ('stig_{0}' -f $stig.Trim('_')).ToLower()
}
