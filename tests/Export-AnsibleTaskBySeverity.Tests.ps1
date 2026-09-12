#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function New-TaskItem {
        param ($Id, $Severity, $Name = 'a task')

        @{
            Rule = [pscustomobject] @{ Id = $Id; Severity = $Severity }
            Task = [ordered] @{ 'name' = $Name; 'ansible.windows.win_feature' = [ordered] @{ 'name' = 'TFTP-Client' } }
        }
    }

    function Export-Tasks {
        param ($Items)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Items = $Items } {
            param ($Items)
            $Items | Export-AnsibleTaskBySeverity
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
}
