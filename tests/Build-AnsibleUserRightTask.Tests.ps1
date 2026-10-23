#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-UserRightRule {
        param ($Id = 'V-150', $Identity = 'Administrators,Guests', $Force = 'False', $OrganizationValueRequired = $false,
            $RawString = 'If any groups or accounts other than the following are granted the right, this is a finding.')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            DisplayName = 'Access this computer from the network'
            Constant = 'SeNetworkLogonRight'
            Identity = $Identity
            Force = $Force
            OrganizationValueRequired = $OrganizationValueRequired
            RawString = $RawString
        }
    }

    # DISA's check text for a deny right, as V-253491 carries it.
    function New-SplitRawString {
        param ([string[]] $Domain, [string[]] $All)

        $text = @(
            'If the following groups or accounts are not defined for the "Deny access to this computer from the network" right, this is a finding:'
            ''
            if ($Domain) { 'Domain Systems Only:'; $Domain; '' }
            if ($All) { 'All Systems:'; $All; '' }
            'Privileged Access Workstations (PAWs) dedicated to the management of Active Directory are exempt from denying the Enterprise Admins and Domain Admins groups.'
        )
        $text -join "`n"
    }

    function Get-UserRightTask {
        param ($Rule)

        (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' -Rule $Rule -StigName 'WindowsClient-11').Task
    }
}

Describe 'Build-AnsibleUserRightTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleUserRightTask' `
        -Module 'ansible.windows.win_user_right' `
        -Factory { New-UserRightRule }

    Context 'the task it builds' {

        # win_user_right takes the constant, not the display name a human reads.
        It 'names the right by its constant' {
            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.name | Should-Be 'SeNetworkLogonRight'
        }

        It 'names the task for the rule id, its severity and the right' {
            $task = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule) -StigName 'WindowsServer-2022-MS').Task

            $task.name | Should-Be 'V-150 | MEDIUM | Access this computer from the network'
        }
    }

    # A rule that forces the list replaces whoever holds the right; one that does not adds to them.
    Context 'whether the rule replaces the identity list or adds to it' {

        It 'sets the action to <Expected> when Force is <Force>' -ForEach @(
            @{ Force = 'True'; Expected = 'set' }
            @{ Force = 'False'; Expected = 'add' }
        ) {
            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Force $Force) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.action | Should-Be $Expected
        }
    }

    # Item 6. PowerShell unrolls a one-element array back to a string on the way out of an if,
    # which is how a single identity came to reach win_user_right as a string.
    Context 'a value the task needs as a list' {

        It 'splits an identity list the rule carries itself' {
            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule) -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.users -join '|' | Should-Be 'Administrators|Guests'
        }

        It 'keeps a single identity a list rather than unrolling it to a string' {
            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Identity 'Administrators') -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.users -is [array] | Should-BeTrue
            @($right.users).Count | Should-Be 1
        }

        # PowerStig ends some identities with a sentence period; the module cannot resolve it. See #143.
        It 'drops a trailing period from an identity' {
            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Identity 'Administrators.,Enterprise Admins.') -StigName 'WindowsServer-2022-MS').Task.'ansible.windows.win_user_right'

            $right.users -join '|' | Should-Be 'Administrators|Enterprise Admins'
        }
    }

    # win_user_right crashes on an empty users list, so a right nobody may hold removes its
    # current holders instead. PowerStig spells that NULL or a blank Identity. See #143.
    Context 'a right nobody may hold' {

        It 'gathers the holders, then removes them, when Identity is <Identity>' -ForEach @(
            @{ Identity = 'NULL' }
            @{ Identity = '' }
        ) {
            $block = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Identity $Identity) -StigName 'WindowsServer-2022-MS').Task.block

            $gather = $block[0]
            $remove = $block[1]
            $gather.Contains('ansible.windows.win_powershell') | Should-BeTrue
            $gather.'ansible.windows.win_powershell'.script | Should-BeLikeString '*SeNetworkLogonRight*'
            $gather.changed_when | Should-BeFalse
            $remove.'ansible.windows.win_user_right'.action | Should-Be 'remove'
            $remove.'ansible.windows.win_user_right'.name | Should-Be 'SeNetworkLogonRight'
            $remove.'ansible.windows.win_user_right'.users | Should-Be "{{ $($gather.register).result }}"
            $remove.when | Should-Be "$($gather.register).result | length > 0"
        }

        It 'never sends an empty users list' {
            $block = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' `
                -Rule (New-UserRightRule -Identity 'NULL') -StigName 'WindowsServer-2022-MS').Task.block

            ($block | ConvertTo-Json -Depth 6) -match '"users":\s*\[\s*\]' | Should-BeFalse
        }
    }
    # DISA splits a right's identities into Domain Systems Only and All Systems; PowerStig flattens
    # them, so the task decides from the target's domain membership. See docs/adr/0025.
    Context 'a domain-only identity' {

        It 'emits the literal list unconditioned when the check text has no Domain Systems Only heading' {
            $task = Get-UserRightTask -Rule (New-UserRightRule)

            $task.'ansible.windows.win_user_right'.users -join '|' | Should-Be 'Administrators|Guests'
            ($task | ConvertTo-Json -Depth 6) | Should-NotBeLikeString '*windows_domain_member*'
        }

        It 'adds the domain-only identities to the all-systems ones only on a domain member' {
            $rule = New-UserRightRule -Identity 'Enterprise Admins,Domain Admins,Local account,Guests' -RawString (
                New-SplitRawString -Domain 'Enterprise Admins group', 'Domain Admins group', 'Local account (see Note below)' -All 'Guests group')

            $task = Get-UserRightTask -Rule $rule

            $task.'ansible.windows.win_user_right'.users |
                Should-Be "{{ ['Guests'] + (['Enterprise Admins', 'Domain Admins', 'Local account'] if ansible_facts['windows_domain_member'] else []) }}"
            $task.when | Should-Be 'stig_client_11_150_when | bool'
        }

        # Not #143's remove-every-holder path: the STIG does not say no one may hold the right.
        It 'skips a rule whose identities are all domain-only off a domain, alongside its toggle' {
            $rule = New-UserRightRule -Identity 'Enterprise Admins,Domain Admins' -RawString (
                New-SplitRawString -Domain 'Enterprise Admins Group', 'Domain Admins Group')

            $task = Get-UserRightTask -Rule $rule

            $task.'ansible.windows.win_user_right'.users | Should-BeCollection @('Enterprise Admins', 'Domain Admins')
            $task.when | Should-BeCollection @('stig_client_11_150_when | bool', "ansible_facts['windows_domain_member']")
        }

        # WindowsServer-2025-MS V-278188, bullets and sentence periods included.
        It 'matches an identity PowerStig ended with a period to its bulleted check text line' {
            $rule = New-UserRightRule -Identity 'Enterprise Admins.,Domain Admins.,Local account .,Guests.' -RawString (
                New-SplitRawString -Domain '- Enterprise Admins group.', '- Domain Admins group.', '- Local account (see Note below).' -All '- Guests group.')

            $task = Get-UserRightTask -Rule $rule

            $task.'ansible.windows.win_user_right'.users |
                Should-Be "{{ ['Guests'] + (['Enterprise Admins', 'Domain Admins', 'Local account'] if ansible_facts['windows_domain_member'] else []) }}"
        }

        It 'fails the conversion, naming the rule, when an identity is under <Case>' -ForEach @(
            @{ Case = 'neither heading'; Domain = @('Enterprise Admin Group', 'Domain Admins Group'); All = @() }
            @{ Case = 'both headings'; Domain = @('Enterprise Admins Group', 'Domain Admins Group'); All = @('Domain Admins Group') }
        ) {
            $rule = New-UserRightRule -Id 'V-253492' -Identity 'Enterprise Admins,Domain Admins' -RawString (
                New-SplitRawString -Domain $Domain -All $All)

            { Get-UserRightTask -Rule $rule } | Should-Throw -ExceptionMessage '*V-253492*RuleCorrection.psd1*'
        }
    }

    Context 'a value the organization decides' {

        It 'interpolates the organization variable rather than inlining a list' {
            $rule = New-UserRightRule -Identity '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-150" Identity="Administrators" />'

            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task.'ansible.windows.win_user_right'

            $right.users | Should-Be '{{ stig_server_2022_150_access_this_computer_from_the_network }}'
        }

        # Splitting on the host instead would make the shape win_user_right receives depend on a
        # jinja expression no test can see, so the whole variable is interpolated as one.
        It 'hands back one reference rather than a split of the reference' {
            $rule = New-UserRightRule -Identity '' -OrganizationValueRequired $true
            $orgSetting = New-ContractOrgSetting '<OrganizationalSetting id="V-150" Identity="Administrators,Guests" />'

            $right = (Invoke-Generator -Generator 'Build-AnsibleUserRightTask' -Rule $rule `
                -StigName 'WindowsServer-2022-MS' -OrganizationalSetting $orgSetting).Task.'ansible.windows.win_user_right'

            @($right.users).Count | Should-Be 1
        }
    }
}
