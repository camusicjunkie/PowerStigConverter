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
    $script:server2025Files = @(
        @{ StigFile = 'WindowsServer-2025-MS-1.1'; Ids = 'V-278085', 'V-278101', 'V-278178', 'V-278180', 'V-278181', 'V-278212'; DomainOnly = 'V-278178', 'V-278181' }
        @{ StigFile = 'WindowsServer-2025-DC-1.1'; Ids = 'V-278085', 'V-278101', 'V-278212'; DomainOnly = @() }
    ) | ForEach-Object { $_ + @{ Present = Test-Path (Join-Path $processed "$($_.StigFile).xml") } }
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
            Repair-PowerStigData -Xml $Xml -OrganizationalSetting $Setting -StigFile $StigFile -Correction $Correction 3>&1
        }

        @{ Xml = $Xml; Setting = $Setting; Warning = @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }) }
    }

    # One processed file of PowerStig's fetched data, loaded and corrected as a conversion loads
    # it, with the warnings its corrections raised.
    function Import-FetchedStig {
        param ([string] $StigFile)

        $output = InModuleScope -ModuleName PowerStigConverter -Parameters @{ StigFile = $StigFile } {
            param ($StigFile)
            Import-PowerStigData -StigName ($StigFile -replace '-[\d.]+$') -Revision ($StigFile -replace '^.+-([\d.]+)$', '$1') 3>&1
        }
        @{
            Stig = $output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            Warning = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        }
    }

    # Converts the loaded STIG's rules of one type that carry one of the ids given.
    function Convert-FetchedRule {
        param ($Stig, [string] $RuleType, [string[]] $Id, $OrganizationalSetting = $Stig.OrganizationalSetting)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Stig = $Stig; RuleType = $RuleType; Id = $Id; Setting = $OrganizationalSetting } {
            param ($Stig, $RuleType, $Id, $Setting)
            ($Stig.Rules | Where-Object PowerStigRule -eq "${RuleType}Rule").StigRule | Where-Object { $_.id -in $Id } |
                ConvertTo-AnsibleTask -RuleType $RuleType -StigProfile (Get-PowerStigProfile -StigName $Stig.StigName) -OrganizationalSetting $Setting
        }
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
                'V-3' = @{ Reason = 'x'; ReplaceInRawString = @(
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
                'V-3' = @{ Reason = 'x'; ReplaceInRawString = @(@{ From = 'Schema Admin Group'; To = 'Schema Admins Group' }) }
            }

            $result.Warning.Count | Should-Be 1
        }

        # More than one match means the text moved on in a way the correction never saw.
        It 'leaves text that occurs more than once alone, and warns' {
            $result = Invoke-Repair -Correction @{
                'V-3' = @{ Reason = 'x'; ReplaceInRawString = @(@{ From = 'Admin Group'; To = 'Admins Group' }) }
            }

            $result.Xml.DISASTIG.UserRightRule.Rule.RawString -split '\r?\n' |
                Should-BeCollection @('Domain Systems Only:', 'Enterprise Admin Group', 'Domain Admin Group')
            $result.Warning.Count | Should-Be 1
            $result.Warning[0].Message | Should-BeLikeString '*Test-1.0 V-3*no longer matches*'
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

    # PowerStig's parser leaves a rule it cannot read as a ManualRule; its own .log hard-codes such a
    # rule's type and fields, and so does this. See docs/adr/0020.
    Context 'hard-coding a rule PowerStig could not parse' {

        BeforeAll {
            function New-ManualXml {
                [xml] @'
<DISASTIG stigid="TEST">
  <ManualRule>
    <Rule id="V-4" severity="medium" dscresource="None">
      <DuplicateOf />
      <OrganizationValueRequired>False</OrganizationValueRequired>
      <OrganizationValueTestString />
      <RawString>Value NameCachedLogonsCount</RawString>
    </Rule>
    <Rule id="V-5" severity="medium" dscresource="None"><RawString>x</RawString></Rule>
  </ManualRule>
</DISASTIG>
'@
            }

            $script:hardCoded = @{
                'V-4' = @{ Reason = 'x'; HardCodedRule = @{
                    From = 'ManualRule'; To = 'RegistryRule'
                    Field = @{
                        DscResource = 'Registry'; Ensure = 'Present'
                        Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
                        ValueName = 'CachedLogonsCount'; ValueType = 'String'; ValueData = ''
                        OrganizationValueRequired = 'True'; OrganizationValueTestString = "'{0}' -le '4'"
                    }
                    OrganizationalSetting = @{ ValueData = '4' }
                } }
            }
        }

        It 'moves the rule to the type the correction names, with its fields' {
            $result = Invoke-Repair -Xml (New-ManualXml) -Setting @{} -Correction $hardCoded
            $rule = $result.Xml.DISASTIG.RegistryRule.Rule

            $rule.id | Should-Be 'V-4'
            $rule.dscresource | Should-Be 'Registry'
            $rule.Key | Should-Be 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            $rule.ValueName | Should-Be 'CachedLogonsCount'
            $rule.ValueType | Should-Be 'String'
            $rule.OrganizationValueRequired | Should-Be 'True'
            $rule.OrganizationValueTestString | Should-Be "'{0}' -le '4'"
            @($result.Xml.DISASTIG.ManualRule.Rule.id) | Should-BeCollection @('V-5')
            $result.Warning.Count | Should-Be 0
        }

        It 'adds the org setting the file has no entry for' {
            $result = Invoke-Repair -Xml (New-ManualXml) -Setting @{} -Correction $hardCoded

            $result.Setting['V-4'].id | Should-Be 'V-4'
            $result.Setting['V-4'].ValueData | Should-Be '4'
        }

        # An entry already there is the organization's answer, or PowerStig's own default.
        It 'keeps an org setting the file already has' {
            [xml] $org = '<OrganizationalSettings><OrganizationalSetting id="V-4" ValueData="2" /></OrganizationalSettings>'
            $result = Invoke-Repair -Xml (New-ManualXml) -Setting @{ 'V-4' = $org.OrganizationalSettings.OrganizationalSetting } -Correction $hardCoded

            $result.Setting['V-4'].ValueData | Should-Be '2'
            $result.Warning.Count | Should-Be 0
        }

        # Once PowerStig parses the rule itself, the correction has nothing left to do.
        It 'leaves a rule that is no longer of the type it expects alone, and warns' {
            $xml = New-ManualXml
            $registry = $xml.DISASTIG.AppendChild($xml.CreateElement('RegistryRule'))
            [void] $registry.AppendChild($xml.DISASTIG.ManualRule.RemoveChild($xml.DISASTIG.ManualRule.Rule[0]))
            $result = Invoke-Repair -Xml $xml -Setting @{} -Correction $hardCoded

            $result.Xml.DISASTIG.RegistryRule.Rule.dscresource | Should-Be 'None'
            $result.Setting.ContainsKey('V-4') | Should-BeFalse
            $result.Warning.Count | Should-Be 1
            $result.Warning[0].Message | Should-BeLikeString '*Test-1.0 V-4*no longer matches*'
        }

        It 'warns when the rule is not in the data' {
            $result = Invoke-Repair -Xml (New-ManualXml) -Setting @{} -Correction @{ 'V-9' = $hardCoded['V-4'] }

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
                ($correction.RemoveEntry -or $correction.OrganizationalSetting -or $correction.Field -or $correction.ReplaceInRawString -or $correction.HardCodedRule) | Should-BeTrue
            }
        }
    }

    # A correction the data has outgrown should be removed. Only checkable where PowerStig's data
    # has been fetched, so it is skipped elsewhere rather than failed.
    It 'still matches the data of <StigFile>' -ForEach $stigFiles -Skip:(-not ($stigFiles | Where-Object Present)) {
        if (-not $Present) { Set-ItResult -Skipped -Because "$StigFile is not in the local PowerStig data" ; return }

        (Import-FetchedStig -StigFile $StigFile).Warning.Message | Should-BeNull
    }

    # PowerStig's 2025 .log forces these to ManualRules (#227).
    It 'sets each hard-coded registry value of <StigFile>' -ForEach $server2025Files {
        if (-not $Present) { Set-ItResult -Skipped -Because "$StigFile is not in the local PowerStig data" ; return }

        $stig = (Import-FetchedStig -StigFile $StigFile).Stig
        $tasks = Convert-FetchedRule -Stig $stig -RuleType Registry -Id $Ids

        @($tasks | ForEach-Object { $_.Rule.id }) | Should-BeEquivalent $Ids
        foreach ($task in $tasks) {
            $task.Task.Contains('ansible.windows.win_regedit') | Should-BeTrue
            $gated = @($task.Task.when) -contains "ansible_facts['windows_domain_member']"
            $gated | Should-Be ($task.Rule.id -in $DomainOnly)
            $task.Incomplete | Should-BeNull
        }
        # An organization value the corrected org settings answer with DISA's 4.
        if ('V-278181' -in $Ids) {
            ($tasks | Where-Object { $_.Rule.id -eq 'V-278181' }).Declaration | Should-MatchString 'cachedlogonscount: .?4.?$'
        }
    }

    # PowerStig's 2025 DC .log forces V-278133 to a ManualRule (#234). It and the four Kerberos
    # lifetimes beside it are set in the Default Domain Policy (docs/adr/0028).
    It 'sets every Kerberos policy of WindowsServer-2025-DC-1.1 in the Default Domain Policy' {
        if (-not (Test-Path (Join-Path $processed 'WindowsServer-2025-DC-1.1.xml'))) { Set-ItResult -Skipped -Because 'WindowsServer-2025-DC-1.1 is not in the local PowerStig data'; return }

        $stig = (Import-FetchedStig -StigFile 'WindowsServer-2025-DC-1.1').Stig
        $tasks = Convert-FetchedRule -Stig $stig -RuleType AccountPolicy -Id V-278133, V-278134, V-278135, V-278136, V-278137

        @($tasks | ForEach-Object { $_.Rule.id }) | Should-BeEquivalent @('V-278133', 'V-278134', 'V-278135', 'V-278136', 'V-278137')
        foreach ($task in $tasks) {
            $task.Task.'ansible.windows.win_powershell'.parameters.Section | Should-Be 'Kerberos Policy'
        }
        ($tasks | Where-Object { $_.Rule.id -eq 'V-278133' }).Task.'ansible.windows.win_powershell'.parameters |
            Should-BeEquivalent ([ordered] @{ Section = 'Kerberos Policy'; Key = 'TicketValidateClient'; Value = 1 })
    }

    # V-253430.b repeats .a's certificate; checking it once is enough.
    It 'gathers each V-253430 certificate of <StigFile> once' -ForEach $clientFiles {
        if (-not $Present) { Set-ItResult -Skipped -Because "$StigFile is not in the local PowerStig data" ; return }

        $store = New-ContractOrgSetting (-join @(
            foreach ($id in 'V-253430.a', 'V-253430.b', 'V-253430.c') {
                '<OrganizationalSetting id="{0}" Location="Cert:\LocalMachine\Disallowed" />' -f $id
            }
        ))

        $stig = (Import-FetchedStig -StigFile $StigFile).Stig
        $task = @{
            All = Convert-FetchedRule -Stig $stig -RuleType RootCertificate -Id V-253430.a, V-253430.b, V-253430.c -OrganizationalSetting $store
            B = Convert-FetchedRule -Stig $stig -RuleType RootCertificate -Id V-253430.b -OrganizationalSetting $store
        }
        $thumbprints = @($task.All.Task.block | Where-Object { $_.Contains('ansible.windows.win_certificate_info') }) |
            ForEach-Object { $_.'ansible.windows.win_certificate_info'.thumbprint }

        $task.B | Should-BeNull
        $thumbprints | Should-BeEquivalent @('9B74964506C7ED9138070D08D5F8B969866560C8', 'D471CA32F7A692CE6CBB6196BD3377FE4DBCD106')
    }
}
