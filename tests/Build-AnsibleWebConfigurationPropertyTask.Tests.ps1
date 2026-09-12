#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function New-WebConfigurationPropertyRule {
        param ($Id = 'V-210', $ConfigSection = '/system.webServer/security/requestFiltering')

        [pscustomobject] @{
            Id = $Id
            Severity = 'medium'
            DuplicateOf = ''
            ConfigSection = $ConfigSection
            Key = 'allowDoubleEscaping'
            Value = 'false'
        }
    }

    function Get-WebConfigTask {
        param ($Rule, $StigId = 'IIS_10-0_Server')

        (Invoke-Generator -Generator 'Build-AnsibleWebConfigurationPropertyTask' -Rule $Rule `
            -StigName 'IISServer-10.0' -ExtraParams @{ StigId = $StigId }).Task
    }
}

Describe 'Build-AnsibleWebConfigurationPropertyTask' {

    Add-GeneratorContractTests -Generator 'Build-AnsibleWebConfigurationPropertyTask' `
        -Module 'ansible.windows.win_dsc' `
        -StigName 'IISServer-10.0' `
        -ExtraParams @{ StigId = 'IIS_10-0_Server' } `
        -Factory { New-WebConfigurationPropertyRule }

    Context 'the task it builds' {

        It 'uses the WebConfigProperty DSC resource' {
            (Get-WebConfigTask -Rule (New-WebConfigurationPropertyRule)).'ansible.windows.win_dsc'.resource_name |
                Should-Be 'WebConfigProperty'
        }

        It 'carries the section, property and value' {
            $dsc = (Get-WebConfigTask -Rule (New-WebConfigurationPropertyRule)).'ansible.windows.win_dsc'

            $dsc.Filter | Should-Be '/system.webServer/security/requestFiltering'
            $dsc.PropertyName | Should-Be 'allowDoubleEscaping'
            $dsc.Value | Should-Be 'false'
        }

        It 'names the task for the rule id, its severity and the property it sets' {
            (Get-WebConfigTask -Rule (New-WebConfigurationPropertyRule)).name |
                Should-BeLikeString 'V-210 | MEDIUM | Ensure false is set to allowDoubleEscaping*'
        }
    }

    # A system.web section lives under the web root; everything else under the app host. A site
    # STIG instead targets one site, whose name the implementing site fills in as a variable.
    Context 'which configuration path the property is set on' {

        It 'targets the web root for a system.web section on a server STIG' {
            $rule = New-WebConfigurationPropertyRule -ConfigSection '/system.web/sessionState'

            (Get-WebConfigTask -Rule $rule).'ansible.windows.win_dsc'.WebsitePath | Should-Be 'MACHINE/WEBROOT'
        }

        It 'targets the app host for any other section on a server STIG' {
            (Get-WebConfigTask -Rule (New-WebConfigurationPropertyRule)).'ansible.windows.win_dsc'.WebsitePath |
                Should-Be 'MACHINE/WEBROOT/APPHOST'
        }

        It 'interpolates the website variable for a site STIG' {
            (Get-WebConfigTask -Rule (New-WebConfigurationPropertyRule) -StigId 'IIS_10-0_Site').'ansible.windows.win_dsc'.WebsitePath |
                Should-BeLikeString 'IIS:\Sites\{{ *_website }}'
        }
    }

    Context 'sub-rules that share a base id' {

        BeforeAll {
            $script:grouped = InModuleScope -ModuleName PowerStigConverter {
                @(
                    [pscustomobject] @{
                        Id = 'V-211.a'; Severity = 'medium'; DuplicateOf = ''
                        ConfigSection = '/system.webServer/security/requestFiltering'
                        Key = 'allowDoubleEscaping'; Value = 'false'
                    }
                    [pscustomobject] @{
                        Id = 'V-211.b'; Severity = 'medium'; DuplicateOf = ''
                        ConfigSection = '/system.webServer/security/requestFiltering'
                        Key = 'allowHighBitCharacters'; Value = 'false'
                    }
                ) | ConvertTo-AnsibleTask -RuleType 'WebConfigurationProperty' -StigName 'IISServer-10.0' -StigId 'IIS_10-0_Server'
            }
        }

        It 'nests both sub-rules in one block' {
            @($grouped).Count | Should-Be 1
            @($grouped.Task.block).Count | Should-Be 2
        }

        It 'guards the block with one toggle named for the base id' {
            $grouped.Task.when | Should-Be 'stig_iisserver_10_0_211_when'
        }

        It 'names the block for the leaf of the shared config section' {
            $grouped.Task.name | Should-Be 'V-211 | MEDIUM | Ensure section requestFiltering is configured'
        }
    }
}
