#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

. $PSScriptRoot/GeneratorContract.ps1

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1
    . $PSScriptRoot/GeneratorContract.ps1

    function Export-OrgValues {
        param ($PowerStigRule, $Rules, $StigName)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{
            PowerStigRule = $PowerStigRule; Rules = $Rules; StigName = $StigName
        } {
            param ($PowerStigRule, $Rules, $StigName)
            [pscustomobject] @{ PowerStigRule = $PowerStigRule; StigRule = $Rules } |
                Export-AnsibleOrganizationValue -StigName $StigName
        }
    }
}

# RoleVariableData.psd1 names the task a generator builds a bare role variable's reference from,
# and Export-AnsibleOrganizationValue.ps1 declares that same name in defaults/ - the two literal
# strings agree only by convention, so this locks the pair down rather than trusting they won't
# drift the way LogPath and website once could have. See docs/adr/0004.
Describe 'RoleVariableData' {

    It 'names the IIS log path the same for the reference and the declaration' {
        $rule = [pscustomobject] @{
            Id = 'V-300'; Severity = 'medium'; DuplicateOf = ''; OrganizationValueRequired = $false
            LogFlags = ''; LogFormat = ''; LogPeriod = ''; LogTargetW3C = ''; LogCustomFieldEntry = ''
        }

        $reference = (Invoke-Generator -Generator 'Build-AnsibleIisLoggingTask' -Rule $rule -StigName 'IISServer-10.0').Task.'ansible.windows.win_dsc'.LogPath
        $declaration = (Export-OrgValues -PowerStigRule 'IisLoggingRule' -Rules @($rule) -StigName 'IISServer-10.0').main_default_org

        $reference | Should-Be '{{ stig_iisserver_10_0_300_logpath }}'
        $declaration | Should-ContainCollection @('stig_iisserver_10_0_300_logpath: ')
    }

    It 'names the IIS website the same for <Generator>''s reference and the declaration' -ForEach @(
        @{ Generator = 'Build-AnsibleWebConfigurationPropertyTask'; RuleType = 'WebConfigurationPropertyRule'; ExtraParams = @{ StigId = 'IIS_10-0_Site' } }
        @{ Generator = 'Build-AnsibleMimeTypeTask'; RuleType = 'MimeTypeRule'; ExtraParams = @{ StigId = 'IIS_10-0_Site' } }
    ) {
        $rule = [pscustomobject] @{
            Id = 'V-310'; Severity = 'medium'; DuplicateOf = ''; OrganizationValueRequired = $false
            ConfigSection = '/system.webServer/security/requestFiltering'; Key = 'allowDoubleEscaping'; Value = 'false'
            Extension = '.exe'; MimeType = 'application/octet-stream'; Ensure = 'Absent'
        }

        $task = (Invoke-Generator -Generator $Generator -Rule $rule -StigName 'IISServer-10.0' -ExtraParams $ExtraParams).Task
        $path = $task.'ansible.windows.win_dsc'.WebsitePath, $task.'ansible.windows.win_dsc'.ConfigurationPath |
            Where-Object { $_ }

        $declaration = (Export-OrgValues -PowerStigRule $RuleType -Rules @($rule) -StigName 'IISServer-10.0').main_default_org

        $path | Should-Be 'IIS:\Sites\{{ stig_iisserver_10_0_310_website }}'
        $declaration | Should-ContainCollection @('stig_iisserver_10_0_310_website: ')
    }
}
