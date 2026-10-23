#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $script:correctionFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source/Files/RuleCorrection.psd1'
    $script:processed = Join-Path $env:LOCALAPPDATA 'PowerStig/source/StigData/Processed'

    $script:stigFiles = (Import-PowerShellDataFile $correctionFile).Keys | ForEach-Object {
        @{ StigFile = $_; Present = Test-Path (Join-Path $processed "$_.xml") }
    }
    $script:clientFiles = 'WindowsClient-11-2.6', 'WindowsClient-11-2.7' | ForEach-Object {
        @{ StigFile = $_; Present = Test-Path (Join-Path $processed "$_.xml") }
    }
}

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    $script:correctionFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'Source/Files/RuleCorrection.psd1'
    $script:processed = Join-Path $env:LOCALAPPDATA 'PowerStig/source/StigData/Processed'

    function New-StigXml {
        [xml] @'
<DISASTIG stigid="TEST">
  <PermissionRule>
    <Rule id="V-1" dscresource="NTFSAccessEntry">
      <AccessControlEntry>
        <Entry><Principal>Administrators</Principal><Rights>FullControl</Rights></Entry>
        <Entry><Principal>(RX)</Principal><Rights>ReadAndExecute</Rights></Entry>
      </AccessControlEntry>
    </Rule>
  </PermissionRule>
  <UserRightRule>
    <Rule id="V-3" dscresource="UserRightsAssignment">
      <Identity>Enterprise Admins,Domain Admins</Identity>
      <RawString>Domain Systems Only:
Enterprise Admin Group
Domain Admin Group</RawString>
    </Rule>
  </UserRightRule>
</DISASTIG>
'@
    }

    function New-OrgSetting {
        param ($Identity = 'Administrators.,Guests.')

        [xml] $org = "<OrganizationalSettings><OrganizationalSetting id=`"V-2`" Identity=`"$Identity`" /></OrganizationalSettings>"
        @{ 'V-2' = $org.OrganizationalSettings.OrganizationalSetting }
    }

    # Runs against the corrections given rather than the shipped file, and hands back the
    # warnings beside the repaired inputs.
    function Invoke-Repair {
        param ($Correction, $Xml = (New-StigXml), $Setting = (New-OrgSetting), $StigFile = 'Test-1.0')

        $warnings = InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Correction = $Correction; Xml = $Xml; Setting = $Setting; StigFile = $StigFile
        } {
            param ($Correction, $Xml, $Setting, $StigFile)
            $saved = $script:ruleCorrection
            try {
                $script:ruleCorrection = @{ $StigFile = $Correction }
                Repair-PowerStigData -Xml $Xml -OrganizationalSetting $Setting -StigFile 'Test-1.0' 3>&1
            }
            finally { $script:ruleCorrection = $saved }
        }

        @{ Xml = $Xml; Setting = $Setting; Warning = @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }) }
    }
}

# PowerStig fixes its own parsing errors with a .log beside each source STIG; RuleCorrection.psd1
# carries the ones its processed data still has. See docs/adr/0020.
Describe 'Repair-PowerStigData' {

    Context 'removing an access control entry' {

        It 'removes the entry the correction names and keeps the rest' {
            $result = Invoke-Repair -Correction @{ 'V-1' = @{ Reason = 'x'; RemoveEntry = @{ Principal = '(RX)' } } }

            @($result.Xml.DISASTIG.PermissionRule.Rule.AccessControlEntry.Entry.Principal) |
                Should-BeCollection @('Administrators')
            $result.Warning.Count | Should-Be 0
        }

        It 'warns when no entry matches, and removes nothing' {
            $result = Invoke-Repair -Correction @{ 'V-1' = @{ Reason = 'x'; RemoveEntry = @{ Principal = 'Server Operators' } } }

            @($result.Xml.DISASTIG.PermissionRule.Rule.AccessControlEntry.Entry).Count | Should-Be 2
            $result.Warning.Count | Should-Be 1
            $result.Warning[0].Message | Should-BeLikeString '*Test-1.0 V-1*no longer matches*'
        }

        It 'warns when the rule is not in the data' {
            $result = Invoke-Repair -Correction @{ 'V-9' = @{ Reason = 'x'; RemoveEntry = @{ Principal = '(RX)' } } }

            $result.Warning.Count | Should-Be 1
        }
    }

    Context 'replacing an organization setting' {

        It 'replaces the attribute while it still holds the value the correction expects' {
            $result = Invoke-Repair -Correction @{
                'V-2' = @{ Reason = 'x'; OrganizationalSetting = @{ Identity = @{ From = 'Administrators.,Guests.'; To = 'Administrators,Guests' } } }
            }

            $result.Setting['V-2'].Identity | Should-Be 'Administrators,Guests'
            $result.Warning.Count | Should-Be 0
        }

        # The data changed under the correction, so applying it could overwrite a real fix.
        It 'leaves a value it does not expect alone, and warns' {
            $result = Invoke-Repair -Setting (New-OrgSetting -Identity 'Administrators') -Correction @{
                'V-2' = @{ Reason = 'x'; OrganizationalSetting = @{ Identity = @{ From = 'Administrators.,Guests.'; To = 'Administrators,Guests' } } }
            }

            $result.Setting['V-2'].Identity | Should-Be 'Administrators'
            $result.Warning.Count | Should-Be 1
        }
    }

    # DISA's check text can misname an identity the rule carries, which ADR 0025's split relies on.
    Context 'replacing text in the check text' {

        It 'replaces each piece of text the correction names' {
            $result = Invoke-Repair -Correction @{
                'V-3' = @{ Reason = 'x'; RawString = @(
                    @{ From = 'Enterprise Admin Group'; To = 'Enterprise Admins Group' }
                    @{ From = 'Domain Admin Group'; To = 'Domain Admins Group' }
                ) }
            }

            $result.Xml.DISASTIG.UserRightRule.Rule.RawString -split '\r?\n' |
                Should-BeCollection @('Domain Systems Only:', 'Enterprise Admins Group', 'Domain Admins Group')
            $result.Warning.Count | Should-Be 0
        }

        It 'warns when the text is no longer there' {
            $result = Invoke-Repair -Correction @{
                'V-3' = @{ Reason = 'x'; RawString = @(@{ From = 'Schema Admin Group'; To = 'Schema Admins Group' }) }
            }

            $result.Warning.Count | Should-Be 1
        }
    }

    Context 'replacing a rule field' {

        BeforeAll {
            function New-CertificateXml {
                [xml] @'
<DISASTIG stigid="TEST">
  <CertificateRule>
    <Rule id="V-3" dscresource="CertificateDSC">
      <CertificateName>Root CA 2,Thumbprint: 9</CertificateName>
      <Thumbprint>Thumbprint: 9B74</Thumbprint>
    </Rule>
  </CertificateRule>
</DISASTIG>
'@
            }
        }

        It 'replaces the field while it still holds the value the correction expects' {
            $result = Invoke-Repair -Xml (New-CertificateXml) -Correction @{
                'V-3' = @{ Reason = 'x'; Field = @{
                    Thumbprint      = @{ From = 'Thumbprint: 9B74'; To = '9B74' }
                    CertificateName = @{ From = 'Root CA 2,Thumbprint: 9'; To = 'Root CA 2' }
                } }
            }

            $result.Xml.DISASTIG.CertificateRule.Rule.Thumbprint | Should-Be '9B74'
            $result.Xml.DISASTIG.CertificateRule.Rule.CertificateName | Should-Be 'Root CA 2'
            $result.Warning.Count | Should-Be 0
        }

        It 'leaves a value it does not expect alone, and warns' {
            $result = Invoke-Repair -Xml (New-CertificateXml) -Correction @{
                'V-3' = @{ Reason = 'x'; Field = @{ Thumbprint = @{ From = 'thumbprint: 9b74'; To = '9B74' } } }
            }

            $result.Xml.DISASTIG.CertificateRule.Rule.Thumbprint | Should-Be 'Thumbprint: 9B74'
            $result.Warning.Count | Should-Be 1
            $result.Warning[0].Message | Should-BeLikeString '*Test-1.0 V-3*no longer matches*'
        }

        It 'warns when the rule is not in the data' {
            $result = Invoke-Repair -Xml (New-CertificateXml) -Correction @{
                'V-9' = @{ Reason = 'x'; Field = @{ Thumbprint = @{ From = 'Thumbprint: 9B74'; To = '9B74' } } }
            }

            $result.Warning.Count | Should-Be 1
        }

        It 'warns when the rule has no such field' {
            $result = Invoke-Repair -Xml (New-CertificateXml) -Correction @{
                'V-3' = @{ Reason = 'x'; Field = @{ Location = @{ From = ''; To = 'Root' } } }
            }

            $result.Warning.Count | Should-Be 1
        }
    }

    Context 'a STIG with no corrections' {

        It 'changes nothing and warns about nothing' {
            $xml = New-StigXml
            $warnings = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Xml = $xml } {
                param ($Xml)
                Repair-PowerStigData -Xml $Xml -OrganizationalSetting @{} -StigFile 'NoSuchStig-1.0' 3>&1
            }

            @($warnings).Count | Should-Be 0
            @($xml.DISASTIG.PermissionRule.Rule.AccessControlEntry.Entry).Count | Should-Be 2
        }
    }
}

Describe 'RuleCorrection.psd1' {

    It 'gives every correction a reason and something to do' {
        $corrections = Import-PowerShellDataFile $correctionFile

        foreach ($stigFile in $corrections.Keys) {
            $stigFile | Should-MatchString '^.+-[\d.]+$'
            foreach ($id in $corrections[$stigFile].Keys) {
                $correction = $corrections[$stigFile][$id]
                $correction.Reason | Should-NotBeNull
                ($correction.RemoveEntry -or $correction.OrganizationalSetting -or $correction.Field -or $correction.RawString) | Should-BeTrue
            }
        }
    }

    # A correction the data has outgrown should be removed. Only checkable where PowerStig's data
    # has been fetched, so it is skipped elsewhere rather than failed.
    It 'still matches the data of <StigFile>' -ForEach $stigFiles -Skip:(-not ($stigFiles | Where-Object Present)) {
        if (-not $Present) { Set-ItResult -Skipped -Because "$StigFile is not in the local PowerStig data" ; return }

        [xml] $xml = Get-Content (Join-Path $processed "$StigFile.xml")
        [xml] $org = Get-Content (Join-Path $processed "$StigFile.org.default.xml")
        $settings = @{}
        foreach ($node in $org.OrganizationalSettings.OrganizationalSetting) { if ($node) { $settings[$node.id] = $node } }

        $warnings = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Xml = $xml; Settings = $settings; StigFile = $StigFile } {
            param ($Xml, $Settings, $StigFile)
            Repair-PowerStigData -Xml $Xml -OrganizationalSetting $Settings -StigFile $StigFile 3>&1
        }

        @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Message | Should-BeNull
    }

    # PowerStig split V-253430.b's raw string at the wrong place; the gather has to get the bare hex.
    It 'gathers V-253430.b of <StigFile> by its bare thumbprint' -ForEach $clientFiles {
        if (-not $Present) { Set-ItResult -Skipped -Because "$StigFile is not in the local PowerStig data" ; return }

        [xml] $xml = Get-Content (Join-Path $processed "$StigFile.xml")
        $store = New-ContractOrgSetting '<OrganizationalSetting id="V-253430.b" Location="Cert:\LocalMachine\Disallowed" />'

        $task = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Xml = $xml; Store = $store; StigFile = $StigFile } {
            param ($Xml, $Store, $StigFile)
            Repair-PowerStigData -Xml $Xml -OrganizationalSetting @{} -StigFile $StigFile 3>$null
            $Xml.DISASTIG.RootCertificateRule.Rule | Where-Object id -eq 'V-253430.b' |
                ConvertTo-AnsibleTask -RuleType RootCertificate -StigName 'WindowsClient-11' -OrganizationalSetting $Store
        }
        $gather = $task.Task.block | Where-Object { $_.Contains('ansible.windows.win_certificate_info') }

        $gather.'ansible.windows.win_certificate_info'.thumbprint | Should-Be '9B74964506C7ED9138070D08D5F8B969866560C8'
        $gather.name | Should-Be 'Gather info for US DOD CCEB Interoperability Root CA 2'
    }
}
