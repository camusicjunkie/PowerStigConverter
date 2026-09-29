function Get-AnsibleVariablePrefix {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    # Every variable the role uses is named from this prefix, so the scaffolding and the
    # generated files must derive it the same way. Ansible variable names allow only letters,
    # digits and underscores, so nothing else may survive into the result.

    # 'All' is a STIG's scope - it covers every release of its product - not a release of its own,
    # so it has no sibling to be told apart from and contributes nothing to any prefix. Dropped
    # before the product is classified, because that is true of a Windows component
    # (WindowsDefender-All) and an application (FireFox-All) alike. See docs/adr/0013.
    $product = $StigName -replace '-All$'

    switch -Regex ($product) {
        # WindowsServer-2022-MS -> server_2022, WindowsServer-2012R2-DC -> server_2012r2,
        # WindowsClient-11 -> client_11. The release suffix is kept so that 2012R2 and a
        # hypothetical 2012 do not collapse onto the same prefix.
        '^Windows(\w+)-(\d+)(R\d)?' {
            $stig = '{0}_{1}{2}' -f $matches[1], $matches[2], $matches[3]
            break
        }
        # A Windows component with no release left to name: WindowsDefender -> defender,
        # WindowsFirewall -> firewall. The word 'Windows' is dropped here for the same reason it is
        # dropped above - every role a Windows STIG generates targets a Windows host.
        '^Windows(\w+)$' {
            $stig = $matches[1]
            break
        }
        # Application STIGs (IIS, SQL Server, .NET, Firefox) keep their own name, sanitised.
        default {
            $stig = $product -replace '[^A-Za-z0-9]+', '_'
        }
    }

    ('stig_{0}' -f $stig.Trim('_')).ToLower()
}
