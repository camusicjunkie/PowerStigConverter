function Get-AnsibleOsAssertion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    # ansible_distribution reports the full product name and edition, for example
    # "Microsoft Windows Server 2022 Datacenter" or "Microsoft Windows 11 Enterprise", so the
    # role asserts on the leading product name only. Linux's ansible_distribution is bare
    # ("RedHat" or "OracleLinux"), and ansible_os_family reports "RedHat" for both - RHEL-9 and
    # OracleLinux-8/9 share it, so OsMajorVersion is what tells them apart. See ADR 0007.
    $osFamily = 'Windows'
    $osMajorVersion = $null

    switch -Regex ($StigName) {
        '^WindowsServer-(\d{4})(R\d)?' {
            $release = if ($matches[2]) { '{0} {1}' -f $matches[1], $matches[2] } else { $matches[1] }
            $description = 'Windows Server {0}' -f $release
            $pattern = 'Microsoft {0}' -f $description
            break
        }
        '^WindowsClient-(\d+)' {
            $description = 'Windows {0}' -f $matches[1]
            $pattern = 'Microsoft {0}' -f $description
            break
        }
        '^RHEL-(\d+)' {
            $osFamily = 'RedHat'
            $osMajorVersion = $matches[1]
            $description = 'RHEL {0}' -f $matches[1]
            $pattern = 'RedHat'
            break
        }
        '^OracleLinux-(\d+)' {
            $osFamily = 'RedHat'
            $osMajorVersion = $matches[1]
            $description = 'Oracle Linux {0}' -f $matches[1]
            $pattern = 'OracleLinux'
            break
        }
        default {
            # Application STIGs (IIS, SQL Server, .NET) are not tied to one Windows release,
            # so they assert only that the host is Windows at all.
            $description = 'Windows'
            $pattern = 'Microsoft {0}' -f $description
        }
    }

    [pscustomobject] @{
        Pattern = $pattern
        Description = $description
        OsFamily = $osFamily
        OsMajorVersion = $osMajorVersion
    }
}
