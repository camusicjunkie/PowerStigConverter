#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures' | Join-Path -ChildPath 'PowerStig'
    $script:stigName = 'WindowsServer-2022-MS'

    # The README documents WindowsServer-2022-MS as giving the stig_server_2022 prefix and
    # asserting Microsoft Windows Server 2022.
    $script:prefix = 'stig_server_2022'

    # Generate the role once; the tests below all read the same output, which is how a user
    # experiences the command - one run, a role on disk.
    $script:outputPath = Join-Path $TestDrive 'generated'
    $script:role = New-AnsiblePlaybook -StigName $stigName -Path $fixtureRoot -OutputPath $outputPath -RoleName 'fixture_role' -WarningAction SilentlyContinue 6>$null

    function Get-RoleFile {
        param ([string] $RelativePath)

        Get-Content -Path (Join-Path $role.Path $RelativePath) -Raw
    }
}

Describe 'New-AnsiblePlaybook' {

    Context 'what the command hands back' {

        It 'returns the role path and the two directories it writes into' {
            $role.Path | Should -Exist
            $role.TaskPath | Should-Be (Join-Path $role.Path 'tasks')
            $role.DefaultPath | Should-Be (Join-Path $role.Path 'defaults' | Join-Path -ChildPath 'main')
        }
    }

    # The README documents the exact tree a run produces.
    Context 'the role directory structure' {

        It 'creates <RelativePath>' -ForEach @(
            @{ RelativePath = 'tasks/main.yml' }
            @{ RelativePath = 'tasks/cat1.yml' }
            @{ RelativePath = 'tasks/cat2.yml' }
            @{ RelativePath = 'tasks/cat3.yml' }
            @{ RelativePath = 'defaults/main/main.yml' }
            @{ RelativePath = 'defaults/main/main_default_cat1.yml' }
            @{ RelativePath = 'defaults/main/main_default_cat2.yml' }
            @{ RelativePath = 'defaults/main/main_default_cat3.yml' }
            @{ RelativePath = 'defaults/main/main_default_org.yml' }
            @{ RelativePath = 'vars/main.yml' }
            @{ RelativePath = 'handlers/main.yml' }
        ) {
            Join-Path $role.Path $RelativePath | Should -Exist
        }
    }

    Context 'the OS assertion in tasks/main.yml' {

        It 'asserts the product name the STIG is for' {
            Get-RoleFile 'tasks/main.yml' | Should-BeLikeString '*Microsoft Windows Server 2022*'
        }

        It 'names the role variables from the prefix derived from the STIG' {
            Get-RoleFile 'tasks/main.yml' | Should-BeLikeString "*${prefix}_cat1*"
        }

        It 'imports each severity file behind its own tag' {
            $main = Get-RoleFile 'tasks/main.yml'

            foreach ($cat in 'cat1', 'cat2', 'cat3') {
                $main | Should-BeLikeString "*import_tasks: $cat.yml*"
            }
        }
    }

    # cat1 is CAT I (high), cat2 is CAT II (medium), cat3 is CAT III (low).
    Context 'splitting tasks by severity' {

        It 'puts the high severity rules in cat1' {
            $cat1 = Get-RoleFile 'tasks/cat1.yml'

            $cat1 | Should-BeLikeString '*V-101*'
            $cat1 | Should-BeLikeString '*V-102*'
        }

        It 'puts the medium severity rules in cat2' {
            $cat2 = Get-RoleFile 'tasks/cat2.yml'

            $cat2 | Should-BeLikeString '*V-100*'
            $cat2 | Should-BeLikeString '*V-104*'
        }

        It 'puts the low severity rules in cat3' {
            $cat3 = Get-RoleFile 'tasks/cat3.yml'

            $cat3 | Should-BeLikeString '*V-105*'
            $cat3 | Should-BeLikeString '*V-106*'
        }

        It 'does not repeat a rule across severity files' {
            $cat1 = Get-RoleFile 'tasks/cat1.yml'
            $cat3 = Get-RoleFile 'tasks/cat3.yml'

            $cat1 | Should-NotBeLikeString '*V-105*'
            $cat3 | Should-NotBeLikeString '*V-101*'
        }
    }

    Context 'translating rules into ansible modules' {

        It 'converts a registry rule to win_regedit with the value type lowercased' {
            $cat1 = Get-RoleFile 'tasks/cat1.yml'

            $cat1 | Should-BeLikeString '*ansible.windows.win_regedit*'
            $cat1 | Should-BeLikeString '*name: SMB1*'
            $cat1 | Should-BeLikeString '*type: dword*'
        }

        It 'converts a user right rule to win_user_right, splitting the identity list' {
            $cat2 = Get-RoleFile 'tasks/cat2.yml'

            $cat2 | Should-BeLikeString '*ansible.windows.win_user_right*'
            $cat2 | Should-BeLikeString '*name: SeNetworkLogonRight*'
            $cat2 | Should-BeLikeString '*- Administrators*'
            $cat2 | Should-BeLikeString '*- Authenticated Users*'
        }

        It 'sets the user right action to set when the rule forces the identity list' {
            Get-RoleFile 'tasks/cat2.yml' | Should-BeLikeString '*action: set*'
        }

        It 'converts an audit policy rule to win_audit_policy_system' {
            $cat3 = Get-RoleFile 'tasks/cat3.yml'

            $cat3 | Should-BeLikeString '*community.windows.win_audit_policy_system*'
            $cat3 | Should-BeLikeString '*subcategory: Credential Validation*'
            $cat3 | Should-BeLikeString '*audit_type: Success*'
        }

        It 'converts a windows feature rule to win_feature' {
            $cat3 = Get-RoleFile 'tasks/cat3.yml'

            $cat3 | Should-BeLikeString '*ansible.windows.win_feature*'
            $cat3 | Should-BeLikeString '*name: Fax*'
            $cat3 | Should-BeLikeString '*state: Absent*'
        }

        It 'converts an account policy rule to win_security_policy with the mapped key' {
            $cat2 = Get-RoleFile 'tasks/cat2.yml'

            $cat2 | Should-BeLikeString '*community.windows.win_security_policy*'
            $cat2 | Should-BeLikeString '*key: MaximumPasswordAge*'
            $cat2 | Should-BeLikeString '*value: 60*'
        }
    }

    # PowerStig splits some rules into sub-rules (V-103.a, V-103.b). They have to become one
    # ansible block so the whole rule is enabled or disabled by a single variable.
    Context 'rules PowerStig split into sub-rules' {

        It 'nests the sub-rules in one block' {
            $cat2 = Get-RoleFile 'tasks/cat2.yml'

            $cat2 | Should-BeLikeString '*block:*'
            $cat2 | Should-BeLikeString '*V-103.a*'
            $cat2 | Should-BeLikeString '*V-103.b*'
        }

        It 'guards the block with one toggle named for the base id, not the sub-rule ids' {
            $cat2 = Get-RoleFile 'tasks/cat2.yml'

            $cat2 | Should-BeLikeString "*when: ${prefix}_103_when*"
            $cat2 | Should-NotBeLikeString "*${prefix}_103_a_when*"
        }
    }

    Context 'rules that must not reach the output' {

        It 'skips a rule PowerStig marked as a duplicate of another' {
            Get-RoleFile 'tasks/cat1.yml' | Should-NotBeLikeString '*V-107*'
        }

        It 'ignores rules that call for documentation or manual intervention' {
            foreach ($cat in 'cat1', 'cat2', 'cat3') {
                $content = Get-RoleFile "tasks/$cat.yml"
                $content | Should-NotBeLikeString '*V-108*'
                $content | Should-NotBeLikeString '*V-109*'
            }
        }
    }

    # Adding support for a new PowerStig rule type means adding one New-Ansible<Type>Task
    # function, so an unknown type has to be survivable rather than fatal.
    Context 'a rule type with no generator' {

        It 'warns which generator is missing and still produces the role' {
            # The warning is raised by a nested module function, which -WarningVariable on the
            # outer call does not collect, so read it off the warning stream instead.
            $warnings = New-AnsiblePlaybook -StigName $stigName -Path $fixtureRoot `
                -OutputPath (Join-Path $TestDrive 'warned') -RoleName 'warned_role' 3>&1 6>$null |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            $warnings.Message -join "`n" |
                Should-BeLikeString '*Build-AnsibleProcessMitigationTask is not currently supported*'
            Join-Path $TestDrive 'warned/warned_role/tasks/cat1.yml' | Should -Exist
        }

        It 'leaves the unsupported rule out of the task files' {
            Get-RoleFile 'tasks/cat2.yml' | Should-NotBeLikeString '*V-110*'
        }
    }

    Context 'the generated defaults' {

        It 'declares the three severity toggles tasks/main.yml imports on' {
            $org = Get-RoleFile 'defaults/main/main_default_org.yml'

            $org | Should-BeLikeString "*${prefix}_cat1: true*"
            $org | Should-BeLikeString "*${prefix}_cat2: true*"
            $org | Should-BeLikeString "*${prefix}_cat3: true*"
        }

        It 'declares a toggle, defaulted on, for each generated task' {
            $cat1Defaults = Get-RoleFile 'defaults/main/main_default_cat1.yml'

            $cat1Defaults | Should-BeLikeString "*${prefix}_101_when: true*"
            $cat1Defaults | Should-BeLikeString "*${prefix}_102_when: true*"
        }

        It 'declares the sub-rule block toggle under its base id' {
            Get-RoleFile 'defaults/main/main_default_cat2.yml' |
                Should-BeLikeString "*${prefix}_103_when: true*"
        }

        # The toggles are derived from the generated tasks, not from the rule list, so a rule
        # the generators skipped cannot leave a toggle behind that guards nothing.
        It 'declares no toggle for a rule marked as a duplicate' {
            Get-RoleFile 'defaults/main/main_default_cat1.yml' |
                Should-NotBeLikeString '*_107_when*'
        }

        It 'declares no toggle for a rule type with no generator' {
            Get-RoleFile 'defaults/main/main_default_cat2.yml' |
                Should-NotBeLikeString '*_110_when*'
        }
    }

    # Where a STIG leaves a value for the implementing site to choose, the task references a
    # role variable and the org settings file supplies its default. Both halves have to come
    # from the STIG data at the path the caller gave, not from a fixed location.
    Context 'values the implementing site has to decide' {

        BeforeAll {
            # The WindowsClient-11 fixture needs an organisation value for V-201, which its org
            # settings file sets to 15. It also leaves V-202 unanswered on purpose, so the
            # command refuses to generate without the opt-out.
            $script:orgRole = New-AnsiblePlaybook -StigName 'WindowsClient-11' -Path $fixtureRoot `
                -OutputPath (Join-Path $TestDrive 'org') -RoleName 'org_role' `
                -AllowIncompleteOrganizationValue `
                -WarningAction SilentlyContinue 6>$null
        }

        It 'has the task reference the role variable rather than a literal value' {
            Get-Content -Path (Join-Path $orgRole.TaskPath 'cat2.yml') -Raw |
                Should-BeLikeString '*stig_client_11_201_account_lockout_duration*'
        }

        It 'defaults that variable to the value from the org settings at the given path' {
            Get-Content -Path (Join-Path $orgRole.DefaultPath 'main_default_org.yml') -Raw |
                Should-BeLikeString '*stig_client_11_201_account_lockout_duration: 15*'
        }
    }

    # A value DISA leaves to the adopting organization is an outstanding decision, not a data
    # error. Generating anyway produced a role that either set an empty value or silently
    # dropped the rule, so the conversion refuses instead. See docs/adr/0001.
    Context 'an organization value nobody has answered' {

        BeforeAll {
            $script:refusedOutput = Join-Path $TestDrive 'refused'

            # V-202 in the WindowsClient-11 fixture is deliberately blank.
            $script:refusal = try {
                New-AnsiblePlaybook -StigName 'WindowsClient-11' -Path $fixtureRoot `
                    -OutputPath $refusedOutput -RoleName 'refused_role' `
                    -WarningAction SilentlyContinue 6>$null
                $null
            }
            catch {
                $_
            }
        }

        It 'refuses to generate the role' {
            $refusal | Should-NotBeNull
        }

        It 'reports the incomplete values as objects rather than only as prose' {
            $incomplete = @($refusal.TargetObject).Where({ $_.RuleId -eq 'V-202' })

            @($incomplete).Count | Should-Be 1
            $incomplete[0].RuleType | Should-Be 'AccountPolicy'
            $incomplete[0].Field | Should-Be 'PolicyValue'
            $incomplete[0].Status | Should-Be 'Unanswered'
        }

        It 'names the unanswered id in the message a human reads' {
            $refusal.Exception.Message | Should-BeLikeString '*V-202*'
        }

        It 'carries an error id a caller can trap on' {
            $refusal.FullyQualifiedErrorId | Should-BeLikeString 'IncompleteOrganizationValue*'
        }

        # Refusing after the scaffold had been written would leave a half-built role behind for
        # the next run to read as real output.
        It 'leaves nothing on disk' {
            Join-Path $refusedOutput 'refused_role' | Should -Not -Exist
        }

        It 'generates anyway, with a warning, when the caller allows it' {
            $allowed = New-AnsiblePlaybook -StigName 'WindowsClient-11' -Path $fixtureRoot `
                -OutputPath (Join-Path $TestDrive 'allowed') -RoleName 'allowed_role' `
                -AllowIncompleteOrganizationValue `
                -WarningVariable warning -WarningAction SilentlyContinue 6>$null

            $allowed.Path | Should -Exist
            $warning.Message | Should-BeLikeString '*V-202*'
        }
    }

    # Generating over a part-filled org settings file must not produce a role that quietly sets
    # an empty value, so the unanswered ones are guarded on the host as well. See docs/adr/0003.
    Context 'what -AllowIncompleteOrganizationValue produces' {

        BeforeAll {
            $script:incomplete = New-AnsiblePlaybook -StigName 'WindowsClient-11' -Path $fixtureRoot `
                -OutputPath (Join-Path $TestDrive 'incomplete') -RoleName 'incomplete_role' `
                -AllowIncompleteOrganizationValue `
                -WarningAction SilentlyContinue 6>$null

            $script:incompleteOrg = Get-Content -Path (Join-Path $incomplete.DefaultPath 'main_default_org.yml') -Raw
            $script:incompleteTasks = Get-Content -Path (Join-Path $incomplete.TaskPath 'cat3.yml') -Raw
        }

        It 'declares the unanswered variable blank for the operator to fill in' {
            $incompleteOrg | Should-BeLikeString '*stig_client_11_202_account_lockout_threshold:*'
        }

        It 'has the task reference it, so filling defaults/ in finishes the role' {
            # Declaring a variable that no task reads is what made filling it in do nothing.
            $incompleteTasks | Should-BeLikeString '*{{ stig_client_11_202_account_lockout_threshold }}*'
        }

        It 'guards it with an assert, so an unfilled value fails the play rather than setting nothing' {
            $incompleteTasks | Should-BeLikeString '*stig_client_11_202_account_lockout_threshold | default("", true) | length > 0*'
        }

        It 'does not guard the value that was answered' {
            $incompleteTasks | Should-NotBeLikeString '*stig_client_11_201_account_lockout_duration | default*'
        }
    }

    Context 'naming the role' {

        It 'names the role after the STIG when no name is given' {
            $defaulted = New-AnsiblePlaybook -StigName $stigName -Path $fixtureRoot `
                -OutputPath (Join-Path $TestDrive 'defaulted') -WarningAction SilentlyContinue 6>$null

            Split-Path -Path $defaulted.Path -Leaf | Should-Be 'windowsserver_2022_ms'
        }

        It 'uses the name it was given instead' {
            Split-Path -Path $role.Path -Leaf | Should-Be 'fixture_role'
        }
    }

    # The README promises re-running is safe: generated files are replaced, and the four
    # scaffolding files are written once so edits to them survive.
    Context 're-running over an existing role' {

        BeforeAll {
            $script:rerunOutput = Join-Path $TestDrive 'rerun'
            $script:rerunRole = New-AnsiblePlaybook -StigName $stigName -Path $fixtureRoot `
                -OutputPath $rerunOutput -RoleName 'rerun_role' -WarningAction SilentlyContinue 6>$null

            # Stand in for a user editing the hand-editable scaffolding, and for a stale
            # generated file from a previous release of the STIG.
            Add-Content -Path (Join-Path $rerunRole.Path 'defaults/main/main.yml') -Value '# an edit the user made'
            Set-Content -Path (Join-Path $rerunRole.Path 'tasks/cat1.yml') -Value '# stale generated content'

            $null = New-AnsiblePlaybook -StigName $stigName -Path $fixtureRoot `
                -OutputPath $rerunOutput -RoleName 'rerun_role' -WarningAction SilentlyContinue 6>$null
        }

        It 'keeps edits to the hand-editable scaffolding' {
            Get-Content -Path (Join-Path $rerunRole.Path 'defaults/main/main.yml') -Raw |
                Should-BeLikeString '*an edit the user made*'
        }

        It 'replaces the generated task files' {
            $cat1 = Get-Content -Path (Join-Path $rerunRole.Path 'tasks/cat1.yml') -Raw

            $cat1 | Should-NotBeLikeString '*stale generated content*'
            $cat1 | Should-BeLikeString '*V-102*'
        }
    }

    Context 'choosing where the role is written' {

        It 'creates an output directory that does not exist yet' {
            $nested = Join-Path $TestDrive 'does/not/exist/yet'

            $created = New-AnsiblePlaybook -StigName $stigName -Path $fixtureRoot `
                -OutputPath $nested -RoleName 'nested_role' -WarningAction SilentlyContinue 6>$null

            $created.Path | Should -Exist
        }
    }
}

Describe 'New-AnsiblePlaybook for a STIG with IIS logging' {

    BeforeAll {
        $script:iisRole = New-AnsiblePlaybook -StigName 'IISServer-10.0' -Path $fixtureRoot `
            -OutputPath (Join-Path $TestDrive 'iis') -RoleName 'iis_role' `
            -WarningAction SilentlyContinue 6>$null

        $script:iisTasks = Get-Content -Path (Join-Path $iisRole.TaskPath 'cat2.yml') -Raw
        $script:iisOrg = Get-Content -Path (Join-Path $iisRole.DefaultPath 'main_default_org.yml') -Raw
    }

    # Nothing in the org settings file says where IIS should write its logs, so the task points
    # at a variable the site fills in. The rule itself carries every other value, so it is not an
    # organisation-value rule - which is exactly the shape that once had the task referencing a
    # variable defaults/ never declared, and a play that failed on an undefined variable.
    Context 'the log path variable' {

        It 'has the task reference it' {
            $iisTasks | Should-BeLikeString '*LogPath:*{{ stig_iisserver_10_0_300_logpath }}*'
        }

        It 'declares it in defaults, so the reference resolves' {
            $iisOrg | Should-BeLikeString '*stig_iisserver_10_0_300_logpath:*'
        }
    }

    # These come off the rule, not the org settings file, so they are written out as values.
    Context 'the logging values the rule carries itself' {

        It 'splits the log flags into a yaml list' {
            $iisTasks | Should-BeLikeString '*- Date*'
            $iisTasks | Should-BeLikeString '*- ClientIP*'
        }

        It 'does not declare a variable for a value the rule already answers' {
            $iisOrg | Should-NotBeLikeString '*logflags*'
        }
    }
}
