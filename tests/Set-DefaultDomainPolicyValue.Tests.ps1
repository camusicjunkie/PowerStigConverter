#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

# The script a DC's Kerberos policy task runs. It is shipped as task text, so it is tested here by
# running it against a SYSVOL tree in TestDrive, with AD and the registry stood in for. See
# docs/adr/0028.
BeforeAll {
    $script:scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source/Files/Set-DefaultDomainPolicyValue.ps1'
    $script:guid = '{31B2F340-016D-11D2-945F-00C04FB984F9}'

    function New-Sysvol {
        param ([string[]] $Template = @('[Unicode]', 'Unicode=yes', '[Kerberos Policy]', 'MaxTicketAge = 10', 'TicketValidateClient = 1', '[Version]', 'signature="$CHICAGO$"'))

        $policy = Join-Path $TestDrive "sysvol/lab.test/Policies/$guid"
        $secedit = Join-Path $policy 'MACHINE/Microsoft/Windows NT/SecEdit'
        Remove-Item (Join-Path $TestDrive 'sysvol') -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Path $secedit -Force
        Set-Content -LiteralPath (Join-Path $secedit 'GptTmpl.inf') -Value $Template -Encoding Unicode
        Set-Content -LiteralPath (Join-Path $policy 'GPT.INI') -Value '[General]', 'Version=5'
        $script:template = Join-Path $secedit 'GptTmpl.inf'
        $script:ini = Join-Path $policy 'GPT.INI'
        $script:ad = @{ Version = 5 }
    }

    function Invoke-PolicyScript {
        param ([string] $Section = 'Kerberos Policy', [string] $Key, [string] $Value, [switch] $CheckMode)

        # Stand-ins for what the script reads on a DC; functions win over cmdlets of the same name.
        function Get-ADDomain { [pscustomobject] @{ DNSRoot = 'lab.test'; DistinguishedName = 'DC=lab,DC=test' } }
        function Get-ItemProperty { [pscustomobject] @{ SysVol = (Join-Path $TestDrive 'sysvol') } }
        function Get-ADObject { [pscustomobject] @{ versionNumber = $ad.Version } }
        function Set-ADObject { param ($Identity, $Replace) $ad.Version = $Replace.versionNumber }

        $Ansible = [pscustomobject] @{ Changed = $null; CheckMode = [bool] $CheckMode }
        & $scriptPath -Section $Section -Key $Key -Value $Value
        $Ansible
    }
}

Describe 'Set-DefaultDomainPolicyValue' {

    BeforeEach { New-Sysvol }

    It 'replaces the key in its section and raises the GPO version' {
        $result = Invoke-PolicyScript -Key MaxTicketAge -Value 8

        $result.Changed | Should-BeTrue
        Get-Content $template | Should-ContainCollection 'MaxTicketAge = 8'
        Get-Content $template | Should-NotContainCollection 'MaxTicketAge = 10'
        $ad.Version | Should-Be 6
        Get-Content $ini | Should-ContainCollection 'Version=6'
    }

    It 'changes nothing, and leaves the version, when the template already holds the value' {
        $result = Invoke-PolicyScript -Key TicketValidateClient -Value 1

        $result.Changed | Should-BeFalse
        $ad.Version | Should-Be 5
        Get-Content $ini | Should-ContainCollection 'Version=5'
    }

    It 'adds a key the section does not have, inside the section' {
        $null = Invoke-PolicyScript -Key MaxClockSkew -Value 5

        $lines = @(Get-Content $template)
        $lines.IndexOf('MaxClockSkew = 5') | Should-BeLessThan $lines.IndexOf('[Version]')
        $lines.IndexOf('MaxClockSkew = 5') | Should-BeGreaterThan $lines.IndexOf('[Kerberos Policy]')
    }

    It 'adds the section when the template has none' {
        New-Sysvol -Template '[Unicode]', 'Unicode=yes'
        $null = Invoke-PolicyScript -Key MaxTicketAge -Value 10

        @(Get-Content $template)[-2..-1] | Should-BeCollection @('[Kerberos Policy]', 'MaxTicketAge = 10')
    }

    It 'reports the change under check mode without writing it' {
        $result = Invoke-PolicyScript -Key MaxTicketAge -Value 8 -CheckMode

        $result.Changed | Should-BeTrue
        Get-Content $template | Should-ContainCollection 'MaxTicketAge = 10'
        $ad.Version | Should-Be 5
    }

    It 'keeps the template UTF-16, as secedit writes it' {
        $null = Invoke-PolicyScript -Key MaxTicketAge -Value 8

        $bytes = [System.IO.File]::ReadAllBytes($template)
        $bytes[0..1] | Should-BeCollection @([byte] 0xFF, [byte] 0xFE)
    }
}
