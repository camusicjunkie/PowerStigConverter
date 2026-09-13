#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-MimeTypeRule {
        param ($Id = 'V-200', $MimeType = 'application/octet-stream', $Extension = '.exe')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            Extension = $Extension
            MimeType = $MimeType
            Ensure = 'Absent'
            OrganizationValueRequired = $false
        }
    }

    function Get-MimeTypeItem {
        param ($Rule, $StigId = 'IIS_10-0_Server')

        Invoke-Generator -Generator 'Build-AnsibleMimeTypeTask' -Rule $Rule `
            -StigName 'IISServer-10.0' -ExtraParams @{ StigId = $StigId }
    }

    function Get-MimeTypeTask {
        param ($Rule, $StigId = 'IIS_10-0_Server')

        (Get-MimeTypeItem -Rule $Rule -StigId $StigId).Task
    }
}

# There is no ansible module for IIS MIME type mappings, so this one goes through win_dsc.
Describe 'Build-AnsibleMimeTypeTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleMimeTypeTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'IISServer-10.0' `
        -ExtraParams @{ StigId = 'IIS_10-0_Server' } `
        -Factory { New-MimeTypeRule }

    Context 'the task it builds' {

        It 'uses the IISMimeTypeMapping DSC resource' {
            (Get-MimeTypeTask -Rule (New-MimeTypeRule)).'ansible.windows.win_dsc'.resource_name |
                Should-Be 'IISMimeTypeMapping'
        }

        It 'carries the extension, mime type and whether it should be there' {
            $dsc = (Get-MimeTypeTask -Rule (New-MimeTypeRule)).'ansible.windows.win_dsc'

            $dsc.Extension | Should-Be '.exe'
            $dsc.MimeType | Should-Be 'application/octet-stream'
            $dsc.Ensure | Should-Be 'Absent'
        }

        It 'names the task for the rule id, its severity and the mapping' {
            (Get-MimeTypeTask -Rule (New-MimeTypeRule)).name |
                Should-Be 'V-200 | MEDIUM | Ensure .exe for application/octet-stream is Absent'
        }
    }

    # A server STIG configures the machine-wide root; a site STIG configures every site the role
    # names, which is a loop rather than a path the operator picks per rule. See #57.
    Context 'where the configuration is applied' {

        It 'targets the machine web root for a server STIG' {
            (Get-MimeTypeTask -Rule (New-MimeTypeRule)).'ansible.windows.win_dsc'.ConfigurationPath |
                Should-Be 'MACHINE/WEBROOT/APPHOST'
        }

        It 'adds no loop for a server STIG, which configures one machine' {
            (Get-MimeTypeTask -Rule (New-MimeTypeRule)).Keys | Should-NotContainCollection 'loop'
        }

        It 'loops every site the role names for a site STIG' {
            $task = Get-MimeTypeTask -Rule (New-MimeTypeRule) -StigId 'IIS_10-0_Site'

            $task.'ansible.windows.win_dsc'.ConfigurationPath | Should-Be 'IIS:\Sites\{{ item }}'
            $task.loop | Should-Be '{{ stig_iisserver_10_0_websites }}'
        }
    }

    Context 'the role variables it declares' {

        It 'declares nothing for a server STIG, which references no website' {
            (Get-MimeTypeItem -Rule (New-MimeTypeRule)).RoleVariable | Should-BeFalsy
        }

        It 'declares the same list a site STIG''s task loops' {
            $item = Get-MimeTypeItem -Rule (New-MimeTypeRule) -StigId 'IIS_10-0_Site'

            $item.RoleVariable | Should-Be 'websites'
            Get-RoleVariableDeclaration -RoleVariable $item.RoleVariable -StigName 'IISServer-10.0' |
                Should-ContainCollection @('stig_iisserver_10_0_websites: []')
        }
    }

    Context 'sub-rules that share a base id' {

        BeforeAll {
            $script:grouped = InModuleScope -ModuleName PowerStigConverter {
                @(
                    [pscustomobject] @{
                        Id = 'V-201.a'; Severity = 'medium'; DuplicateOf = ''
                        Extension = '.exe'; MimeType = 'binary/octet-stream'; Ensure = 'Absent'
                        OrganizationValueRequired = $false
                    }
                    [pscustomobject] @{
                        Id = 'V-201.b'; Severity = 'medium'; DuplicateOf = ''
                        Extension = '.dll'; MimeType = 'binary/octet-stream'; Ensure = 'Absent'
                        OrganizationValueRequired = $false
                    }
                ) | ConvertTo-AnsibleTask -RuleType 'MimeType' -StigName 'IISServer-10.0' -StigId 'IIS_10-0_Server'
            }
        }

        It 'nests both sub-rules in one block' {
            @($grouped).Count | Should-Be 1
            @($grouped.Task.block).Count | Should-Be 2
        }

        It 'guards the block with one toggle named for the base id' {
            $grouped.Task.when | Should-Be 'stig_iisserver_10_0_201_when'
        }

        It 'names the block for the leaf of the shared mime type' {
            $grouped.Task.name | Should-Be 'V-201 | MEDIUM | Ensure octet-stream MIME types are set'
        }
    }
}
