function Get-PowerStigProfile {
    <#
    .SYNOPSIS
        A STIG's profile: its target and naming, derived once from its STIG name, revision and
        stigid.
    .DESCRIPTION
        The only place a STIG name or stigid is parsed. Everything else asks the profile: dispatch
        for the OS family, the adapters for the target, the naming functions for the variable
        prefix, the scaffold for the OS assertion. See docs/adr/0029.

        A product StigProduct.psd1 does not list fails, rather than being guessed at.
    .OUTPUTS
        StigName, Product, Revision, StigId; OsFamily, OsMajorVersion, OsPattern, OsDescription;
        Target (DomainController, MemberServer, Client or nothing); IisScope (Server, Site or
        nothing); VariablePrefix; RoleName.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName,

        [string] $Revision,

        [string] $StigId
    )

    $productName = ($StigName -split '-', 2)[0]
    $product = $script:stigProduct[$productName]
    if ($null -eq $product) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new(
                "'$StigName' is a STIG of product '$productName', which StigProduct.psd1 does not list. Add it there with its OsFamily."
            ),
            'StigProductUnknown',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $StigName
        ))
    }

    # ansible_facts['distribution'] reports the full product name and edition, for example
    # "Microsoft Windows Server 2022 Datacenter" or "Microsoft Windows 11 Enterprise", so the
    # role asserts on the leading product name only. Linux's is bare ("RedHat" or "OracleLinux"),
    # and ansible_facts['os_family'] reports "RedHat" for both, so OsMajorVersion is what tells
    # RHEL-9 and OracleLinux-8/9 apart. See ADR 0007.
    $osMajorVersion = $null
    switch -Regex ($StigName) {
        '^WindowsServer-(\d{4})(R\d)?' {
            $release = if ($matches[2]) { '{0} {1}' -f $matches[1], $matches[2] } else { $matches[1] }
            $osDescription = 'Windows Server {0}' -f $release
            $osPattern = 'Microsoft {0}' -f $osDescription
            break
        }
        '^WindowsClient-(\d+)' {
            $osDescription = 'Windows {0}' -f $matches[1]
            $osPattern = 'Microsoft {0}' -f $osDescription
            break
        }
        '^RHEL-(\d+)' {
            $osMajorVersion = $matches[1]
            $osDescription = 'RHEL {0}' -f $matches[1]
            $osPattern = 'RedHat'
            break
        }
        '^OracleLinux-(\d+)' {
            $osMajorVersion = $matches[1]
            $osDescription = 'Oracle Linux {0}' -f $matches[1]
            $osPattern = 'OracleLinux'
            break
        }
        default {
            # Application STIGs (IIS, SQL Server, .NET) are not tied to one Windows release, so
            # they assert only that the host is Windows at all.
            $osDescription = 'Windows'
            $osPattern = 'Microsoft {0}' -f $osDescription
        }
    }

    $target = if ($product['Target']) { $product['Target'] }
        elseif ($productName -eq 'WindowsServer') { @{ DC = 'DomainController'; MS = 'MemberServer' }[($StigName -split '-')[-1]] }

    # A server STIG configures the machine-wide path; a site STIG every site the role names.
    $iisScope = if ($StigId -match 'IIS_.+_Server') { 'Server' } elseif ($productName -like 'IIS*') { 'Site' }

    # 'All' is a STIG's scope - it covers every release of its product - not a release of its own,
    # so it has no sibling to be told apart from and contributes nothing to a prefix or a role
    # name. See docs/adr/0013 and 0019.
    $scoped = $StigName -replace '-All$'

    # Every variable the role uses is named from this prefix. Ansible variable names allow only
    # letters, digits and underscores, so nothing else may survive into it.
    switch -Regex ($scoped) {
        # WindowsServer-2022-MS -> server_2022, WindowsServer-2012R2-DC -> server_2012r2,
        # WindowsClient-11 -> client_11. The release suffix is kept so that 2012R2 and a
        # hypothetical 2012 do not collapse onto the same prefix.
        '^Windows(\w+)-(\d+)(R\d)?' {
            $stem = '{0}_{1}{2}' -f $matches[1], $matches[2], $matches[3]
            break
        }
        # A Windows component with no release left to name: WindowsDefender -> defender,
        # WindowsFirewall -> firewall. The word 'Windows' is dropped here for the same reason it is
        # dropped above - every role a Windows STIG generates targets a Windows host.
        '^Windows(\w+)$' {
            $stem = $matches[1]
            break
        }
        # Application STIGs (IIS, SQL Server, .NET, Firefox) keep their own name, sanitised.
        default {
            $stem = $scoped -replace '[^A-Za-z0-9]+', '_'
        }
    }

    [pscustomobject] @{
        StigName = $StigName
        Product = $productName
        Revision = $Revision
        StigId = $StigId
        OsFamily = $product['OsFamily']
        OsMajorVersion = $osMajorVersion
        OsPattern = $osPattern
        OsDescription = $osDescription
        Target = $target
        IisScope = $iisScope
        VariablePrefix = ('stig_{0}' -f $stem.Trim('_')).ToLower()
        RoleName = $scoped.ToLower() -replace '[^\w]+', '_'
    }
}
