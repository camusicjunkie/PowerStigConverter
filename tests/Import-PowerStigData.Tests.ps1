#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'

    function Import-Stig {
        param ($StigName, $Path = $fixtureRoot, $Revision, $Correction)

        $params = @{ StigName = $StigName; Path = $Path }
        if ($Revision) { $params.Revision = $Revision }
        if ($null -ne $Correction) { $params.Correction = $Correction }
        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Params = $params } {
            param ($Params)
            Import-PowerStigData @Params
        }
    }

    # A data tree in TestDrive holding one STIG and its org settings, for the cases the fixtures
    # do not cover.
    function New-StigData {
        param ([string] $Name, [string] $Xml, [string] $Org)

        $root = Join-Path $TestDrive $Name
        $processed = Join-Path $root 'source/StigData/Processed'
        $null = New-Item -ItemType Directory -Path $processed -Force
        Set-Content -Path (Join-Path $processed "$Name.xml") -Value $Xml
        if ($Org) { Set-Content -Path (Join-Path $processed "$Name.org.default.xml") -Value $Org }
        $root
    }
}

Describe 'Import-PowerStigData' {

    # The STIG name is the file name without its revision; the newest revision wins. See #237.
    Context 'finding the STIG' {

        It 'loads the newest revision of the STIG named' {
            (Import-Stig -StigName 'WindowsServer-2022-MS').StigFile | Should-Be 'WindowsServer-2022-MS-2.7'
        }

        It 'loads the revision it is asked for' {
            (Import-Stig -StigName 'WindowsServer-2022-MS' -Revision '1.2').StigFile | Should-Be 'WindowsServer-2022-MS-1.2'
        }

        It 'reads the STIG id from the file' {
            (Import-Stig -StigName 'WindowsClient-8').StigId | Should-NotBeNull
        }

        # A prefix matched the DC and MS files both, and the conversion died parsing two files
        # as one.
        It 'refuses a partial name, naming the STIGs it could mean' {
            $refusal = try { Import-Stig -StigName 'WindowsServer-2022' } catch { $_ }

            $refusal.FullyQualifiedErrorId | Should-BeLikeString 'StigNotFound*'
            $refusal.Exception.Message | Should-BeLikeString '*WindowsServer-2022-DC, WindowsServer-2022-MS*'
        }

        It 'refuses a name no downloaded STIG has' {
            $refusal = try { Import-Stig -StigName 'NotAStig' } catch { $_ }

            $refusal.FullyQualifiedErrorId | Should-BeLikeString 'StigNotFound*'
            $refusal.TargetObject | Should-Be 'NotAStig'
            $refusal.Exception.Message | Should-BeLikeString '*Copy-PowerStigFile*'
        }

        It 'refuses a revision that is not there' {
            $refusal = try { Import-Stig -StigName 'WindowsServer-2022-MS' -Revision '9.9' } catch { $_ }

            $refusal.FullyQualifiedErrorId | Should-BeLikeString 'StigNotFound*'
        }
    }

    # Loading the org settings once into a map by rule id is what gives the conversion a single
    # point at which its inputs can be judged complete.
    Context 'the org settings' {

        It 'keys the settings by rule id, keeping the node' {
            $settings = (Import-Stig -StigName 'WindowsClient-8').OrganizationalSetting

            $settings.Keys | Should-ContainCollection 'V-201'
            $settings['V-201'].PolicyValue | Should-Be '15'
        }

        # A blank value is data, not an absence; the distinction is what lets an unanswered
        # setting be reported differently from a missing one.
        It 'keeps an entry whose value is blank, and has none for a rule the file does not cover' {
            $settings = (Import-Stig -StigName 'WindowsClient-8').OrganizationalSetting

            $settings.ContainsKey('V-202') | Should-BeTrue
            $settings['V-202'].PolicyValue | Should-Be ''
            $settings.ContainsKey('V-999') | Should-BeFalse
        }

        It 'reads the org settings file of the same revision' {
            $root = New-StigData -Name 'Pair-2.0' -Xml '<DISASTIG stigid="P" />' `
                -Org '<OrganizationalSettings><OrganizationalSetting id="V-1" PolicyValue="2" /></OrganizationalSettings>'
            $processed = Join-Path $root 'source/StigData/Processed'
            Set-Content -Path (Join-Path $processed 'Pair-1.0.xml') -Value '<DISASTIG stigid="P" />'
            Set-Content -Path (Join-Path $processed 'Pair-1.0.org.default.xml') -Value '<OrganizationalSettings><OrganizationalSetting id="V-1" PolicyValue="1" /></OrganizationalSettings>'

            (Import-Stig -StigName 'Pair' -Path $root).OrganizationalSetting['V-1'].PolicyValue | Should-Be '2'
            (Import-Stig -StigName 'Pair' -Path $root -Revision '1.0').OrganizationalSetting['V-1'].PolicyValue | Should-Be '1'
        }

        It 'returns an empty map for a file with no settings' {
            $root = New-StigData -Name 'Empty-1.0' -Xml '<DISASTIG stigid="E" />' -Org '<OrganizationalSettings />'
            $settings = (Import-Stig -StigName 'Empty' -Path $root).OrganizationalSetting

            $settings -is [hashtable] | Should-BeTrue
            $settings.Count | Should-Be 0
        }

        # The same failure style as the completeness check this feeds. See docs/adr/0002.
        It 'refuses a STIG with no org settings file, with an error id a caller can trap on' {
            $root = New-StigData -Name 'NoOrg-1.0' -Xml '<DISASTIG stigid="N" />'
            $refusal = try { Import-Stig -StigName 'NoOrg' -Path $root } catch { $_ }

            $refusal.FullyQualifiedErrorId | Should-BeLikeString 'OrgSettingsFileNotFound*'
            $refusal.TargetObject | Should-Be 'NoOrg'
            $refusal.Exception.Message | Should-BeLikeString '*NoOrg-1.0*'
        }
    }

    # Corrections run before the rules are gathered by type, since one can change a rule's type,
    # and Manual rules are dropped only after. See docs/adr/0020 and #227.
    Context 'corrections' {

        BeforeAll {
            $script:manualRoot = New-StigData -Name 'Hard-1.0' -Xml @'
<DISASTIG stigid="H">
  <ManualRule>
    <Rule id="V-4" severity="medium" dscresource="None"><DuplicateOf /><RawString>Value NameX</RawString></Rule>
    <Rule id="V-5" severity="medium" dscresource="None"><RawString>x</RawString></Rule>
  </ManualRule>
</DISASTIG>
'@ -Org '<OrganizationalSettings />'

            $script:hardCoded = @{ 'Hard-1.0' = @{ 'V-4' = @{ Reason = 'x'; HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'Registry'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Test'; ValueName = 'X'; ValueType = 'Dword'; ValueData = '1' }
            } } } }
        }

        It 'gathers a rule a correction hard-codes under its new type, and drops the Manual rules' {
            $stig = Import-Stig -StigName 'Hard' -Path $manualRoot -Correction $hardCoded

            @($stig.Rules.PowerStigRule) | Should-BeCollection @('RegistryRule')
            $stig.Rules[0].StigRule.id | Should-Be 'V-4'
        }

        It 'applies only the corrections of the file it loaded' {
            $stig = Import-Stig -StigName 'Hard' -Path $manualRoot -Correction @{ 'Hard-2.0' = $hardCoded['Hard-1.0'] }

            @($stig.Rules).Count | Should-Be 0
        }

        It 'passes on the warning for a correction the data has outgrown' {
            $stale = @{ 'Hard-1.0' = @{ 'V-9' = $hardCoded['Hard-1.0']['V-4'] } }
            $warnings = @(InModuleScope -ModuleName PowerStigConverter -Parameters @{ Root = $manualRoot; Correction = $stale } {
                param ($Root, $Correction)
                Import-PowerStigData -StigName 'Hard' -Path $Root -Correction $Correction 3>&1
            } | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            @($warnings).Count | Should-Be 1
            $warnings[0].Message | Should-BeLikeString '*Hard-1.0 V-9*'
        }
    }
}
