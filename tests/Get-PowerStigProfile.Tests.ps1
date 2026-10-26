#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $processed = Join-Path $env:LOCALAPPDATA 'PowerStig/source/StigData/Processed'
    $script:fetched = @(Get-ChildItem $processed -Filter *.xml -ErrorAction SilentlyContinue |
        Where-Object Name -notlike '*.org.default.xml' |
        ForEach-Object { $_.BaseName -replace '-[\d.]+$' } | Sort-Object -Unique |
        ForEach-Object { @{ StigName = $_ } })
    # Pester refuses an empty -ForEach; one placeholder reports the data as missing instead.
    if ($fetched.Count -eq 0) { $script:fetched = @(@{ StigName = $null }) }
}

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Get-Profile {
        param ([string] $StigName, [string] $StigId)
        New-TestStigProfile -StigName $StigName -StigId $StigId
    }
}

# A STIG name and stigid are parsed here and nowhere else. See docs/adr/0029.
Describe 'Get-PowerStigProfile' {

    # tasks/main.yml asserts the target OS by matching ansible_distribution against OsPattern and
    # names it in the failure with OsDescription. ansible_distribution reports the product name
    # with an edition after it, so OsPattern is the leading product name only.
    Context 'the OS a role asserts' {

        It 'asserts <Pattern> for <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2022-MS'; Pattern = 'Microsoft Windows Server 2022'; Description = 'Windows Server 2022' }
            @{ StigName = 'WindowsServer-2022-DC'; Pattern = 'Microsoft Windows Server 2022'; Description = 'Windows Server 2022' }
            @{ StigName = 'WindowsServer-2012R2-DC'; Pattern = 'Microsoft Windows Server 2012 R2'; Description = 'Windows Server 2012 R2' }
            @{ StigName = 'WindowsClient-11'; Pattern = 'Microsoft Windows 11'; Description = 'Windows 11' }
            @{ StigName = 'WindowsClient-10'; Pattern = 'Microsoft Windows 10'; Description = 'Windows 10' }
            # Application STIGs are not tied to one Windows release.
            @{ StigName = 'IISServer-10.0'; Pattern = 'Microsoft Windows'; Description = 'Windows' }
            @{ StigName = 'SqlServer-2022-Instance'; Pattern = 'Microsoft Windows'; Description = 'Windows' }
            @{ StigName = 'DotNetFramework-4'; Pattern = 'Microsoft Windows'; Description = 'Windows' }
        ) {
            $stigProfile = Get-Profile -StigName $StigName

            $stigProfile.OsPattern | Should-Be $Pattern
            $stigProfile.OsDescription | Should-Be $Description
            $stigProfile.OsFamily | Should-Be 'Windows'
            $stigProfile.OsMajorVersion | Should-BeNull
        }

        # RHEL and OracleLinux share ansible_os_family ('RedHat'), so OsMajorVersion is what tells
        # them apart. See docs/adr/0007.
        It 'asserts <Pattern> for <StigName>, from the RedHat family' -ForEach @(
            @{ StigName = 'RHEL-9'; Pattern = 'RedHat'; Description = 'RHEL 9'; MajorVersion = '9' }
            @{ StigName = 'OracleLinux-8'; Pattern = 'OracleLinux'; Description = 'Oracle Linux 8'; MajorVersion = '8' }
            @{ StigName = 'OracleLinux-9'; Pattern = 'OracleLinux'; Description = 'Oracle Linux 9'; MajorVersion = '9' }
        ) {
            $stigProfile = Get-Profile -StigName $StigName

            $stigProfile.OsPattern | Should-Be $Pattern
            $stigProfile.OsDescription | Should-Be $Description
            $stigProfile.OsFamily | Should-Be 'RedHat'
            $stigProfile.OsMajorVersion | Should-Be $MajorVersion
        }
    }

    Context 'the host a STIG targets' {

        It 'targets <Target> for <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2025-DC'; Target = 'DomainController' }
            @{ StigName = 'WindowsServer-2025-MS'; Target = 'MemberServer' }
            @{ StigName = 'WindowsClient-11'; Target = 'Client' }
        ) {
            (Get-Profile -StigName $StigName).Target | Should-Be $Target
        }

        It 'names no target for <StigName>' -ForEach @(
            @{ StigName = 'WindowsDefender-All' }
            @{ StigName = 'IISSite-10.0' }
            @{ StigName = 'RHEL-9' }
        ) {
            (Get-Profile -StigName $StigName).Target | Should-BeNull
        }

        # A server STIG configures the machine-wide path; a site STIG every site the role names.
        It 'reads the IIS scope <Scope> from stigid <StigId>' -ForEach @(
            @{ StigName = 'IISServer-10.0'; StigId = 'IIS_10-0_Server'; Scope = 'Server' }
            @{ StigName = 'IISSite-10.0'; StigId = 'IIS_10-0_Site'; Scope = 'Site' }
        ) {
            (Get-Profile -StigName $StigName -StigId $StigId).IisScope | Should-Be $Scope
        }

        It 'has no IIS scope outside IIS' {
            (Get-Profile -StigName 'WindowsServer-2025-MS' -StigId 'MS_Windows_Server_2025_MS_STIG').IisScope | Should-BeNull
        }
    }

    # Every variable the role uses is named from the prefix. See docs/adr/0013.
    Context 'the variable prefix' {

        It 'derives <Expected> from <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2022-MS'; Expected = 'stig_server_2022' }
            @{ StigName = 'WindowsServer-2012R2-DC'; Expected = 'stig_server_2012r2' }
            @{ StigName = 'WindowsServer-2012-DC'; Expected = 'stig_server_2012' }
            @{ StigName = 'WindowsClient-11'; Expected = 'stig_client_11' }
            @{ StigName = 'WindowsDefender-All'; Expected = 'stig_defender' }
            @{ StigName = 'WindowsFirewall-All'; Expected = 'stig_firewall' }
            @{ StigName = 'IISServer-10.0'; Expected = 'stig_iisserver_10_0' }
            @{ StigName = 'DotNetFramework-4'; Expected = 'stig_dotnetframework_4' }
            @{ StigName = 'SqlServer-2016-Instance'; Expected = 'stig_sqlserver_2016_instance' }
            @{ StigName = 'FireFox-All'; Expected = 'stig_firefox' }
        ) {
            (Get-Profile -StigName $StigName).VariablePrefix | Should-Be $Expected
        }

        It 'emits only lowercase letters, digits and underscores for <StigName>' -ForEach @(
            @{ StigName = 'IISSite-10.0' }
            @{ StigName = 'Office-365ProPlus' }
            @{ StigName = 'MS-Edge' }
            @{ StigName = 'Adobe-AcrobatReader' }
            @{ StigName = 'Office-System2016.' }
        ) {
            (Get-Profile -StigName $StigName).VariablePrefix | Should-MatchString '^stig_[a-z0-9_]*[a-z0-9]$'
        }
    }

    # 'All' is a STIG's scope, not a release, so the role is not named for it. See docs/adr/0019.
    Context 'the role name' {

        It 'names <Expected> for <StigName>' -ForEach @(
            @{ StigName = 'WindowsServer-2022-MS'; Expected = 'windowsserver_2022_ms' }
            @{ StigName = 'WindowsClient-11'; Expected = 'windowsclient_11' }
            @{ StigName = 'IISServer-10.0'; Expected = 'iisserver_10_0' }
            @{ StigName = 'WindowsDefender-All'; Expected = 'windowsdefender' }
            @{ StigName = 'FireFox-All'; Expected = 'firefox' }
        ) {
            (Get-Profile -StigName $StigName).RoleName | Should-Be $Expected
        }
    }

    Context 'a product StigProduct.psd1 does not list' {

        It 'refuses it, naming the product and the table' {
            $refusal = try { Get-Profile -StigName 'Ubuntu-18.04' } catch { $_ }

            $refusal.FullyQualifiedErrorId | Should-BeLikeString 'StigProductUnknown*'
            $refusal.Exception.Message | Should-BeLikeString "*'Ubuntu'*StigProduct.psd1*"
        }
    }

    # A new product forces a decision rather than a guess. Only checkable where PowerStig's data
    # has been fetched. Ubuntu is in PowerStig's data but has no converter.
    It 'has a product entry for every fetched STIG, <StigName>' -ForEach $fetched {
        if (-not $StigName) { Set-ItResult -Skipped -Because 'PowerStig''s data has not been fetched'; return }
        if ($StigName -like 'Ubuntu-*') { Set-ItResult -Skipped -Because 'Ubuntu has no converter'; return }

        Get-Profile -StigName $StigName | Should-NotBeNull
    }
}

# Nothing but the profile builder reads a STIG name or stigid apart. See docs/adr/0029.
Describe 'STIG name parsing' {

    It 'happens only in Get-PowerStigProfile' {
        $source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source'
        $parse = '\$(\w+\.)?(StigName|StigId)\b\s*-(not)?(match|like|replace)|switch\s+-Regex\s*\(\s*\$(\w+\.)?Stig(Name|Id)'

        $offenders = Get-ChildItem $source -Filter *.ps1 -Recurse |
            Where-Object Name -notin 'Get-PowerStigProfile.ps1' |
            Select-String -Pattern $parse |
            ForEach-Object { '{0}:{1}: {2}' -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

        $offenders | Should-BeNull
    }
}
