#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    # A single-item result collapses to a scalar crossing the function boundary either way, so
    # every call site below wraps the call itself in @() rather than relying on this to preserve
    # the array shape.
    function Convert-Task {
        param ($Rule, $RuleType, $StigName = 'WindowsServer-2022-MS', $OrganizationalSetting = @{})

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            Rule = $Rule; RuleType = $RuleType; StigName = $StigName; OrganizationalSetting = $OrganizationalSetting
        } {
            param ($Rule, $RuleType, $StigName, $OrganizationalSetting)
            @($Rule | ConvertTo-AnsibleTask -RuleType $RuleType -StigName $StigName -OrganizationalSetting $OrganizationalSetting)
        }
    }

    function Get-ExpectedToggle {
        param ($TaskId, $StigName = 'WindowsServer-2022-MS')

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ TaskId = $TaskId; StigName = $StigName } {
            param ($TaskId, $StigName)
            Get-AnsibleToggleName -TaskId $TaskId -StigName $StigName
        }
    }

    # Never resolves an organization value: WindowsFeature has no entry in OrganizationData.psd1.
    function New-WindowsFeatureRule {
        param ($Id = 'V-200', $DuplicateOf = '', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = $DuplicateOf
            Name = 'TFTP-Client'; Ensure = 'Absent'; OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    function New-AccountPolicyRule {
        param ($Id = 'V-100', $DuplicateOf = '', $OrganizationValueRequired = $false)

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = $DuplicateOf
            PolicyName = 'Maximum password age'; PolicyValue = '60'; OrganizationValueRequired = $OrganizationValueRequired
        }
    }

    # Always Group = $true, and gives its two tasks explicit names - a fit for both grouping
    # cases ConvertTo-AnsibleTask decides on its own.
    function New-RootCertificateRule {
        param ($Id = 'V-180', $DuplicateOf = '')

        [pscustomobject] @{
            Id = $Id; Severity = 'medium'; DuplicateOf = $DuplicateOf
            CertificateName = 'DoD Root CA 3'; Thumbprint = 'D73CA91102A2204A36459ED32213B467D7CE97FB'
            OrganizationValueRequired = $true
        }
    }

    function New-RootStore {
        New-TestOrgSetting '<OrganizationalSetting id="V-180" Location="Cert:\LocalMachine\Root" />'
    }
}

Describe 'ConvertTo-AnsibleTask' {

    Context 'a rule that duplicates another' {

        # Covered by the rule it points at, so it must produce no output at all - not an empty
        # task, and not a toggle in defaults/ guarding nothing.
        It 'skips it' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule -DuplicateOf 'V-099') -RuleType 'AccountPolicy')

            $result.Count | Should-Be 0
        }
    }

    # WindowsServer-2025-MS-1.1's V-278193.c: no DuplicateOf, not org-decided, and no fields at
    # all - resolving its store path threw on the empty Location and failed the whole conversion.
    Context 'an unparsed rule' {

        It 'skips it' {
            $rule = [pscustomobject] @{
                Id = 'V-180.c'; Severity = 'medium'; DuplicateOf = ''; DscResource = 'none'
                CertificateName = ''; Thumbprint = ''; Location = ''; OrganizationValueRequired = $false
            }

            $result = @(Convert-Task -Rule $rule -RuleType 'RootCertificate' 3>$null)

            $result.Count | Should-Be 0
        }

        It 'warns that it was skipped, naming it' {
            $rule = [pscustomobject] @{
                Id = 'V-180.c'; Severity = 'medium'; DuplicateOf = ''; DscResource = 'none'
                CertificateName = ''; Thumbprint = ''; Location = ''; OrganizationValueRequired = $false
            }

            $warned = @(Convert-Task -Rule $rule -RuleType 'RootCertificate' 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $warned.Count | Should-Be 1
            $warned[0].Message | Should-BeLikeString '*V-180.c*'
        }
    }

    Context 'a rule type OrganizationData.psd1 says nothing about' {

        # Resolve-AnsibleOrganizationValue throws for a rule type it has no entry for, so a rule
        # type reaching it here despite the guard would fail the conversion outright rather than
        # producing the task below.
        It 'never resolves an organization value, even when the rule asks for one' {
            $rule = New-WindowsFeatureRule -OrganizationValueRequired $true

            $result = @(Convert-Task -Rule $rule -RuleType 'WindowsFeature')

            $result.Count | Should-Be 1
        }
    }

    Context 'task naming' {

        It 'names an ungrouped task from the rule id, its severity and the detail the adapter reports' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule) -RuleType 'AccountPolicy')

            $result[0].Task.name | Should-Be 'V-100 | MEDIUM | Maximum password age'
        }

        # The adapter names a task outright only for members of a block it builds for itself -
        # here, the register/assert pair a certificate rule always produces.
        It 'keeps the name the adapter supplies for one of a rule''s own tasks' {
            $result = @(Convert-Task -Rule (New-RootCertificateRule) -RuleType 'RootCertificate' -OrganizationalSetting (New-RootStore))

            $result[0].Task.block[0].name | Should-Be 'Gather info for DoD Root CA 3'
        }
    }

    Context 'the conditional toggle' {

        It 'guards an ungrouped task with the toggle for the rule' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule) -RuleType 'AccountPolicy')

            $result[0].Task.when | Should-Be (Get-ExpectedToggle -TaskId 'V-100')
        }

        # A sub-rule shares its base id's toggle, so switching the requirement off has to turn
        # off every task the requirement produced.
        It 'guards a grouped block with the toggle for the base id, not the sub-rule id' {
            $result = @(Convert-Task -Rule (New-RootCertificateRule -Id 'V-180.b') -RuleType 'RootCertificate' `
                -OrganizationalSetting (New-TestOrgSetting '<OrganizationalSetting id="V-180.b" Location="Cert:\LocalMachine\Root" />'))

            $result[0].Task.when | Should-Be (Get-ExpectedToggle -TaskId 'V-180')
        }
    }

    Context 'deciding whether a rule becomes a block' {

        It 'wraps a rule the adapter marks Group into a block named for the base id, severity and group detail' {
            $result = @(Convert-Task -Rule (New-RootCertificateRule) -RuleType 'RootCertificate' -OrganizationalSetting (New-RootStore))

            $result[0].Task.name | Should-BeLikeString 'V-180 | MEDIUM | *'
            $result[0].Task.Contains('block') | Should-BeTrue
        }

        # Sub-rules of one requirement share a block so an operator switches the requirement off
        # rather than one of its halves, even for a rule type whose adapter never asks for a group.
        It 'wraps a sub-rule into a block even when the adapter does not ask for one' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule -Id 'V-100.b') -RuleType 'AccountPolicy')

            $result[0].Task.Contains('block') | Should-BeTrue
        }

        It 'leaves an ordinary single-task rule ungrouped' {
            $result = @(Convert-Task -Rule (New-AccountPolicyRule) -RuleType 'AccountPolicy')

            $result[0].Task.Contains('block') | Should-BeFalse
        }
    }
}

# A rule type that cannot be expressed as one task per rule returns a handler alongside its
# task - the single write several rules notify. These drive the channel through a probe adapter
# rather than through SslSettings, so what is under test is the channel and not that generator.
Describe 'ConvertTo-AnsibleTask handler channel' {

    BeforeAll {
        function Convert-ProbeTask {
            param ($Built, $Rule = ([pscustomobject] @{ Id = 'V-300'; Severity = 'medium'; DuplicateOf = '' }))

            InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rule = $Rule; Built = $Built } {
                param ($Rule, $Built)

                # The adapter is reached by name, so one defined here stands in for a generator.
                function Build-AnsibleHandlerProbeTask {
                    param ($Rule, $StigName, $StigId, $Resolution)
                    $Built
                }

                @($Rule | ConvertTo-AnsibleTask -RuleType 'HandlerProbe' -StigName 'IISSite-10.0')
            }
        }

        $script:probeBuilt = @{
            Task = @{ Detail = 'contribute the ssl flags'; Body = @{ 'ansible.builtin.set_fact' = @{ flags = 'Ssl' } } }
            Handler = @{ Name = 'apply_ssl_settings'; Body = @{ 'ansible.windows.win_dsc' = @{ resource_name = 'SslSettings' } } }
        }
    }

    It 'carries the handler through beside the task' {
        $item = Convert-ProbeTask -Built $probeBuilt

        @($item.Handler).Count | Should-Be 1
        $item.Handler[0].'ansible.windows.win_dsc'.resource_name | Should-Be 'SslSettings'
    }

    # notify addresses a handler by name, so the name is the generator's to state - not one built
    # from the rule id and severity the way a task's is.
    It 'names the handler exactly what the generator asked for' {
        (Convert-ProbeTask -Built $probeBuilt).Handler[0].name | Should-Be 'apply_ssl_settings'
    }

    # The toggle guards the rule's own task, which is the thing that notifies; a handler that
    # carried one too would be switched off by a variable no operator knows names it.
    It 'leaves the handler unguarded' {
        $handler = (Convert-ProbeTask -Built $probeBuilt).Handler[0]

        $handler.Contains('when') | Should-BeFalse
    }

    It 'reports no handler for a rule type that returns none' {
        $item = Convert-ProbeTask -Built @{ Task = @{ Detail = 'set it'; Body = @{ 'ansible.windows.win_dsc' = @{} } } }

        @($item.Handler).Count | Should-Be 0
    }
}

# ADR-0015: a generator offers the candidates its sub-rules might agree on, strongest first, and
# the block is named from the strongest they all agree on. Driven through a probe adapter rather
# than through Registry, so what is under test is the naming and not that generator's candidates.
Describe 'ConvertTo-AnsibleTask block naming' {

    BeforeAll {
        # One sub-rule per Detail given, in order: '.a' offers the first, '.b' the second. Each
        # Detail is the candidates that sub-rule offers, strongest first, pipe-delimited - a
        # nested array would flatten on its way through the array literal, and a single candidate
        # is passed as the bare string a generator with nothing to prefer returns.
        function Convert-NamingProbe {
            param ([string[]] $Detail)

            InModuleScope -ModuleName PowerStigConverter -Parameters @{ Detail = $Detail } {
                param ($Detail)

                $letter = 'a', 'b', 'c', 'd'
                $rules = @(for ($i = 0; $i -lt $Detail.Count; $i++) {
                    [pscustomobject] @{
                        Id = 'V-400.{0}' -f $letter[$i]; Severity = 'medium'; DuplicateOf = ''
                        # The candidates ride on the rule: a variable shared with the adapter does
                        # not survive the module scope ConvertTo-AnsibleTask calls it in.
                        Detail = if ($Detail[$i] -match '\|') { $Detail[$i] -split '\|' } else { $Detail[$i] }
                    }
                })

                function Build-AnsibleNamingProbeTask {
                    param ($Rule, $StigName, $StigId, $Resolution)

                    @{
                        GroupDetail = $Rule.Detail
                        Task = @{ Detail = 'set it'; Body = @{ 'ansible.builtin.debug' = @{ msg = $Rule.Id } } }
                    }
                }

                @($rules | ConvertTo-AnsibleTask -RuleType 'NamingProbe' -StigName 'WindowsServer-2022-MS')
            }
        }
    }

    It 'names the block from the strongest candidate every sub-rule agrees on' {
        $item = @(Convert-NamingProbe -Detail 'Alpha|EnableThing', 'Beta|EnableThing')

        $item[0].Task.name | Should-Be 'V-400 | MEDIUM | EnableThing'
    }

    It 'prefers the stronger candidate when the sub-rules agree on both' {
        $item = @(Convert-NamingProbe -Detail 'Alpha|EnableThing', 'Alpha|EnableThing')

        $item[0].Task.name | Should-Be 'V-400 | MEDIUM | Alpha'
    }

    It 'unions the strongest candidates when the sub-rules agree on none' {
        $item = @(Convert-NamingProbe -Detail 'Alpha|One', 'Beta|Two')

        $item[0].Task.name | Should-Be 'V-400 | MEDIUM | Alpha, Beta'
    }

    # Every generator but Registry offers one candidate, so the union is still what a rule type
    # with nothing to prefer gets - nxFileLine's several files, RootCertificate's several
    # certificates.
    It 'unions a bare string, which is one candidate' {
        $item = @(Convert-NamingProbe -Detail '/etc/ssh/sshd_config', '/etc/pam.d/system-auth')

        $item[0].Task.name | Should-Be 'V-400 | MEDIUM | /etc/ssh/sshd_config, /etc/pam.d/system-auth'
    }

    # A sub-rule cannot agree at a rank it does not reach, so a shorter list ends the search
    # rather than matching whatever happens to sit beside it.
    It 'does not agree at a rank a sub-rule offers nothing for' {
        $item = @(Convert-NamingProbe -Detail 'Alpha|EnableThing', 'Beta')

        $item[0].Task.name | Should-Be 'V-400 | MEDIUM | Alpha, Beta'
    }
}

# Each sub-rule names its own organization variables, so the block a requirement collapses into
# has to carry every member's - the gate and defaults/ read them off it. See docs/adr/0016.
Describe 'ConvertTo-AnsibleTask carrying what a block''s sub-rules leave for defaults/' {

    BeforeAll {
        $subRules = @(
            [pscustomobject] @{
                Id = 'V-300.a'; Severity = 'medium'; DuplicateOf = ''
                PolicyName = 'Maximum password age'; PolicyValue = ''; OrganizationValueRequired = $true
            }
            [pscustomobject] @{
                Id = 'V-300.b'; Severity = 'medium'; DuplicateOf = ''
                PolicyName = 'Minimum password age'; PolicyValue = ''; OrganizationValueRequired = $true
            }
        )
        $setting = New-TestOrgSetting @'
<OrganizationalSetting id="V-300.a" PolicyValue="60" />
<OrganizationalSetting id="V-300.b" PolicyValue="" />
'@
        $script:block = @(Convert-Task -Rule $subRules -RuleType 'AccountPolicy' -OrganizationalSetting $setting)
    }

    It 'collapses both sub-rules into one block' {
        $block.Count | Should-Be 1
    }

    It 'declares the variables of every sub-rule, not only the first' {
        $declaration = $block[0].Declaration -join "`n"

        $declaration | Should-BeLikeString '*300_a*60*'
        $declaration | Should-BeLikeString '*300_b*'
    }

    It 'reports the unanswered value of a sub-rule after the first' {
        @($block[0].Incomplete.RuleId) | Should-BeCollection @('V-300.b')
    }
}

# A requirement's sub-rules collapse into one block wherever they sit in the STIG, carrying what
# every one of them hands on. Driven through a probe adapter that reads its handler and role
# variable off the rule, so what is under test is the collapse and not any one generator. See #125.
Describe 'ConvertTo-AnsibleTask collapsing sub-rules into a block' {

    BeforeAll {
        function New-ProbeRule {
            param ($Id, $Handler, $RoleVariable)

            [pscustomobject] @{ Id = $Id; Severity = 'medium'; DuplicateOf = ''; Handler = $Handler; RoleVariable = $RoleVariable }
        }

        function Convert-CollapseProbe {
            param ($Rules)

            InModuleScope -ModuleName PowerStigConverter -Parameters @{ Rules = $Rules } {
                param ($Rules)

                function Build-AnsibleCollapseProbeTask {
                    param ($Rule, $StigName, $StigId, $Resolution)

                    @{
                        GroupDetail = 'probe'
                        Task = @{ Detail = 'set it'; Body = @{ 'ansible.builtin.debug' = @{ msg = $Rule.Id } } }
                        Handler = if ($Rule.Handler) { @{ Name = $Rule.Handler; Body = @{ 'ansible.builtin.debug' = @{ msg = $Rule.Handler } } } } else { $null }
                        RoleVariable = $Rule.RoleVariable
                    }
                }

                @($Rules | ConvertTo-AnsibleTask -RuleType 'CollapseProbe' -StigName 'WindowsServer-2022-MS')
            }
        }
    }

    It 'collapses sub-rules the STIG does not list together into one block' {
        $result = @(Convert-CollapseProbe -Rules @(
            (New-ProbeRule 'V-501.a'), (New-ProbeRule 'V-502'), (New-ProbeRule 'V-501.b')
        ))

        $block = $result | Where-Object { $_.Task.name -like 'V-501 |*' }
        @($block).Count | Should-Be 1
        $block.Task.block.'ansible.builtin.debug'.msg | Should-BeCollection @('V-501.a', 'V-501.b')
    }

    It 'emits in STIG order, a block where its first sub-rule sits' {
        $result = @(Convert-CollapseProbe -Rules @(
            (New-ProbeRule 'V-510'), (New-ProbeRule 'V-501.a'), (New-ProbeRule 'V-500'), (New-ProbeRule 'V-501.b')
        ))

        # Joined, because Should-BeCollection does not compare order. The ids are out of sequence
        # so that sorting them could not pass this either.
        ($result.Task.name | ForEach-Object { ($_ -split ' ')[0] }) -join ',' | Should-Be 'V-510,V-501,V-500'
    }

    It 'carries the handlers and role variables of every sub-rule, not only the first' {
        $result = @(Convert-CollapseProbe -Rules @(
            (New-ProbeRule 'V-600.a' -Handler 'apply_a' -RoleVariable 'websites')
            (New-ProbeRule 'V-600.b' -Handler 'apply_b' -RoleVariable 'webapppools')
        ))

        @($result).Count | Should-Be 1
        $result[0].Handler.name | Should-BeCollection @('apply_a', 'apply_b')
        $result[0].RoleVariable | Should-BeCollection @('websites', 'webapppools')
    }

    It 'produces nothing for no rules' {
        @(Convert-CollapseProbe -Rules @()).Count | Should-Be 0
    }
}
