#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-TaskItem {
        param ($Id, $Severity, $Name = 'a task', [string[]] $RoleVariable = @())

        @{
            Rule = [pscustomobject] @{ Id = $Id; Severity = $Severity }
            Task = [ordered] @{ 'name' = $Name; 'ansible.windows.win_feature' = [ordered] @{ 'name' = 'TFTP-Client' } }
            RoleVariable = $RoleVariable
        }
    }

    function Export-Tasks {
        param ($Items, $StigName = 'WindowsServer-2022-MS')

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Items = $Items; StigName = $StigName } {
            param ($Items, $StigName)
            $Items | Export-AnsibleTaskBySeverity -StigName $StigName
        }
    }
}

# The exporter decides what each severity file holds; writing it is New-AnsiblePlaybook's job, so
# none of this needs a filesystem. See #19.
Describe 'Export-AnsibleTaskBySeverity' {

    Context 'splitting tasks across the severity files' {

        BeforeAll {
            $script:files = Export-Tasks -Items @(
                New-TaskItem -Id 'V-1' -Severity 'high' -Name 'high one'
                New-TaskItem -Id 'V-2' -Severity 'medium' -Name 'medium one'
                New-TaskItem -Id 'V-3' -Severity 'low' -Name 'low one'
            )
        }

        It 'names a file for each DISA category' {
            $files.Keys | Should-BeCollection @('cat1', 'cat2', 'cat3')
        }

        It 'puts a <Severity> rule in <File>' -ForEach @(
            @{ Severity = 'high'; File = 'cat1'; Name = 'high one' }
            @{ Severity = 'medium'; File = 'cat2'; Name = 'medium one' }
            @{ Severity = 'low'; File = 'cat3'; Name = 'low one' }
        ) {
            $files.$File -join "`n" | Should-BeLikeString "*$Name*"
        }

        It 'yields yaml rather than the task object' {
            $files.cat1 -join "`n" | Should-BeLikeString '*ansible.windows.win_feature*'
        }
    }

    # tasks/main.yml imports all three unconditionally, so a file with nothing in it still has to
    # be named - Save-AnsibleRoleFile is what decides not to write an empty one.
    Context 'a severity with no rules' {

        It 'still names the file' {
            $files = Export-Tasks -Items @(New-TaskItem -Id 'V-1' -Severity 'high')

            $files.Keys | Should-ContainCollection @('cat3')
        }
    }

    Context 'a severity outside the DISA categories' {

        It 'drops a rule that has no file to go in' {
            $files = Export-Tasks -Items @(New-TaskItem -Id 'V-9' -Severity 'informational' -Name 'nowhere')

            ($files.Values | ForEach-Object { $_ }) -join "`n" | Should-NotBeLikeString '*nowhere*'
        }
    }

    Context 'no tasks at all' {

        It 'still names all three files' {
            $files = Export-Tasks -Items @()

            $files.Keys | Should-BeCollection @('cat1', 'cat2', 'cat3')
        }
    }

    # An empty list is not an error in ansible, it is a no-op, so a role whose website list is
    # still [] hardens nothing and says nothing. ADR-0001 says a conversion that cannot be honest
    # fails loudly; this is that failure wearing a no-op's clothes. See #57.
    Context 'the role-scoped lists the tasks loop over' {

        BeforeAll {
            $script:guarded = Export-Tasks -Items @(
                New-TaskItem -Id 'V-1' -Severity 'high' -RoleVariable @('websites')
                New-TaskItem -Id 'V-2' -Severity 'medium' -RoleVariable @('websites', 'webapppools')
            )
        }

        It 'asserts the list is not empty, naming the file that answers it' {
            $guarded.cat1 -join "`n" | Should-BeLikeString '*stig_server_2022_websites | length > 0*'
            $guarded.cat1 -join "`n" | Should-BeLikeString '*defaults/main/main.yml*'
        }

        It 'asserts once per distinct list, however many tasks referenced it' {
            ([regex]::Matches($guarded.cat2 -join "`n", 'stig_server_2022_websites \| length')).Count | Should-Be 1
            $guarded.cat2 -join "`n" | Should-BeLikeString '*stig_server_2022_webapppools | length > 0*'
        }

        # tasks/main.yml imports each severity file behind its own tag, so a run of --tags cat2
        # alone has to assert too - which means repeating the guard in every file that has tasks.
        It 'repeats the guard in each severity file that has tasks' {
            $guarded.cat1 -join "`n" | Should-BeLikeString '*stig_server_2022_webapppools | length > 0*'
        }

        It 'puts the asserts before the tasks they guard' {
            $guarded.cat1[0] | Should-BeLikeString '*ansible.builtin.assert*'
        }

        # Save-AnsibleRoleFile skips an empty file; a guard with no tasks behind it would make one.
        It 'leaves a severity with no tasks empty' {
            $guarded.cat3 | Should-BeFalsy
        }

        It 'guards nothing when no task references a list' {
            $files = Export-Tasks -Items @(New-TaskItem -Id 'V-1' -Severity 'high')

            $files.cat1 -join "`n" | Should-NotBeLikeString '*ansible.builtin.assert*'
        }
    }
}
