function Get-AnsibleOsAssertion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    # ansible_distribution reports the full product name and edition, for example
    # "Microsoft Windows Server 2022 Datacenter" or "Microsoft Windows 11 Enterprise", so the
    # role asserts on the leading product name only.
    switch -Regex ($StigName) {
        '^WindowsServer-(\d{4})(R\d)?' {
            $release = if ($matches[2]) { '{0} {1}' -f $matches[1], $matches[2] } else { $matches[1] }
            $description = 'Windows Server {0}' -f $release
            break
        }
        '^WindowsClient-(\d+)' {
            $description = 'Windows {0}' -f $matches[1]
            break
        }
        default {
            # Application STIGs (IIS, SQL Server, .NET) are not tied to one Windows release,
            # so they assert only that the host is Windows at all.
            $description = 'Windows'
        }
    }

    [pscustomobject] @{
        Pattern = 'Microsoft {0}' -f $description
        Description = $description
    }
}
