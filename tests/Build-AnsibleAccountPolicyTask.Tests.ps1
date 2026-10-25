#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

# At file scope, not only in BeforeAll: Pester builds the test tree at discovery, so
# Add-GeneratorContractTests has to exist before Describe runs.
. $PSScriptRoot/GeneratorContract.ps1

BeforeDiscovery {
    $processed = Join-Path $env:LOCALAPPDATA 'PowerStig/source/StigData/Processed'
    $script:stigFiles = @(Get-ChildItem $processed -Filter 'Windows*.xml' -ErrorAction SilentlyContinue |
        Where-Object Name -notlike '*.org.default.xml' |
        ForEach-Object { @{ StigFile = $_.BaseName; Path = $_.FullName } })
    # Pester refuses an empty -ForEach; one placeholder reports the data as missing instead.
    if ($stigFiles.Count -eq 0) { $script:stigFiles = @(@{ StigFile = 'the local PowerStig data'; Path = $null }) }
}

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    # Again at run time, because It bodies execute in a scope that only sees what BeforeAll set
    # up - this is where the contract's helpers have to be.
    . $PSScriptRoot/GeneratorContract.ps1

    function New-AccountPolicyRule {
        param ($Id = 'V-100', $OrganizationValueRequired = $false, $PolicyName = 'Maximum password age', $PolicyValue = '60')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            # Flattens to a key of AccountPolicyData.psd1, where the section and key live.
            PolicyName = $PolicyName
            PolicyValue = $PolicyValue
            OrganizationValueRequired = $OrganizationValueRequired
        }
    }
}

Describe 'Build-AnsibleAccountPolicyTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleAccountPolicyTask' `
        -Module 'community.windows.win_security_policy' `
        -Factory { New-AccountPolicyRule }

    Context 'the task it builds' {

        It 'looks the section and key up rather than taking them off the rule' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $policy = $task.'community.windows.win_security_policy'
            $policy.section | Should-Be 'System Access'
            $policy.key | Should-Be 'MaximumPasswordAge'
        }

        # win_security_policy wants the number, and yaml would otherwise read a quoted 60 as text.
        It 'passes a numeric value through as a number' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $task.'community.windows.win_security_policy'.value | Should-Be 60
            $task.'community.windows.win_security_policy'.value -is [int] | Should-BeTrue
        }

        It 'names the task for the rule id, its severity and the policy' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-100 | MEDIUM | Maximum password age'
        }
    }

    # Item 7 of the contract. The value DISA leaves to the adopting organization never reaches the
    # task as a literal - it is declared in defaults/ and interpolated. See docs/adr/0003.
    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a value' {
            $rule = New-AccountPolicyRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="15" />'

            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task

            $task.'community.windows.win_security_policy'.value |
                Should-Be '{{ stig_server_2022_100_maximum_password_age }}'
        }

        # Normally the conversion refuses outright; this is what -AllowIncompleteOrganizationValue
        # produces instead, so an unanswered value fails the play rather than setting nothing.
        It 'guards an unanswered value with an assert' {
            $rule = New-AccountPolicyRule -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-100" PolicyValue="" />'

            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task

            $task.block[0].'ansible.builtin.assert' | Should-NotBeNull
        }
    }

    # The domain owns account policy on a domain member, so a local write there changes nothing or
    # is overwritten. See #232.
    Context 'where the rule runs' {

        It 'runs off a domain only, after its toggle, outside a domain controller (<StigName>)' -ForEach @(
            @{ StigName = 'WindowsServer-2025-MS' }
            @{ StigName = 'WindowsClient-11' }
        ) {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' -Rule (New-AccountPolicyRule) -StigName $StigName).Task

            @($task.when)[-1] | Should-Be "not ansible_facts['windows_domain_member']"
            @($task.when)[0] | Should-BeLikeString '*_when | bool'
        }

        # On a domain controller secedit's write is the domain's policy, so it runs there.
        It 'runs on a domain controller whatever its membership' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2025-DC').Task

            ($task | ConvertTo-Json -Depth 6) | Should-NotBeLikeString '*windows_domain_member*'
        }

        # #175 set these through Set-ADDefaultDomainPasswordPolicy; the threshold-0 gap was the cause.
        It 'sets <name> on a domain controller with secedit' -ForEach @(
            @{ name = 'Account lockout duration'; key = 'LockoutDuration' }
            @{ name = 'Reset account lockout counter after'; key = 'ResetLockoutCount' }
        ) {
            $rule = New-AccountPolicyRule -PolicyName $name -PolicyValue '15'
            $task = (Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' -Rule $rule -StigName 'WindowsServer-2025-DC').Task

            $task.'community.windows.win_security_policy'.key | Should-Be $key
            $task.'community.windows.win_security_policy'.value | Should-Be 15
        }
    }

    # secedit lists LockoutDuration and ResetLockoutCount only while the threshold is above 0.
    Context 'the lockout threshold' {

        It 'is marked to run ahead of the rest of its severity' {
            $output = Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' `
                -Rule (New-AccountPolicyRule -PolicyName 'Account lockout threshold' -PolicyValue '3') -StigName 'WindowsServer-2025-MS'

            $output.First | Should-BeTrue
        }

        It 'leaves every other policy unmarked' {
            $output = Invoke-Generator -Generator 'Build-AnsibleAccountPolicyTask' -Rule (New-AccountPolicyRule) -StigName 'WindowsServer-2025-MS'

            $output.First | Should-BeFalse
        }
    }
}

# Every Windows STIG but 2019 lists lockout duration before the threshold. See #232.
Describe 'Account policy in PowerStig''s data' {

    It 'sets the lockout threshold before duration and reset in <StigFile>' -ForEach $stigFiles {
        if (-not $Path) { Set-ItResult -Skipped -Because 'PowerStig''s data has not been fetched'; return }

        [xml] $xml = Get-Content $Path -Raw
        $rules = @($xml.DISASTIG.AccountPolicyRule.Rule | Where-Object { $_ })
        if (-not ($rules | Where-Object PolicyName -eq 'Account lockout threshold')) {
            Set-ItResult -Skipped -Because "$StigFile has no lockout threshold"; return
        }

        $yaml = InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rules = $rules; StigName = ($StigFile -replace '-[\d.]+$') } {
            param ($Rules, $StigName)
            $files = $Rules | ConvertTo-AnsibleTask -RuleType AccountPolicy -StigName $StigName | Export-AnsibleTaskBySeverity -StigName $StigName
            ($files.cat1, $files.cat2, $files.cat3 | ForEach-Object { $_ }) -join "`n"
        }

        $threshold = $yaml.IndexOf('key: LockoutBadCount')
        foreach ($key in 'LockoutDuration', 'ResetLockoutCount') {
            $at = $yaml.IndexOf("key: $key")
            if ($at -ge 0) { $threshold | Should-BeLessThan $at }
        }
    }
}
