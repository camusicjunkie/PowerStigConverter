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

# A role variable is one the implementing site fills in, and its reference and its declaration are
# two literal strings that agree only by convention - so each pair is locked down here rather than
# trusted not to drift the way LogPath and website once could have. See docs/adr/0004.
#
# The two scopes are pinned differently because they are sourced differently. A per-rule one is
# named in RoleVariableData.psd1 and read by the exporter, so the psd1 and the generator have to
# agree. A role-scoped one comes from the generator's own RoleVariable output key, so there is
# nothing for the psd1 to disagree with - each generator's test file pins its own pair, and this
# checks the psd1 no longer claims to know about them. See #57.
Describe 'RoleVariableData' {

    Context 'a variable named per rule' {

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
    }

    # Keeping the psd1 as the source for these was the live alternative #57 declined: it is a
    # single source too, but it cannot tell that a Server STIG references no website, so the
    # exporter would have had to learn the site-vs-machine predicate as well.
    Context 'a variable named once for the role' {

        It 'says nothing about the role-scoped lists, which the generators own' {
            $data = InModuleScope -ModuleName PowerStigConverter { $script:roleVariableData }

            $data.Keys | Should-BeCollection @('IisLogging')
            ($data.Values.PerRole | Where-Object { $_ }) | Should-BeFalsy
        }
    }
}
