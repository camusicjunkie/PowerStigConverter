#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:splat = @{ StigId = 'IIS_10-0_Server'; MachinePath = 'MACHINE/WEBROOT/APPHOST'; StigName = 'IISSite-10.0' }

    function Get-Scope {
        param ($StigId)

        $siteSplat = $splat.Clone()
        $siteSplat.StigId = $StigId

        Invoke-PrivateCommand -Command 'Get-AnsibleIisScope' -Splat $siteSplat
    }
}

Describe 'Get-AnsibleIisScope' {

    Context 'a server STIG' {

        It 'returns the machine-wide path the caller supplied' {
            (Get-Scope -StigId 'IIS_10-0_Server').Path | Should-Be 'MACHINE/WEBROOT/APPHOST'
        }

        # The machine is one thing, so there is nothing to loop over and nothing to declare - which
        # is what stops an IISServer role declaring a website list no task ever reads. See #57.
        It 'has nothing to loop over and no role variable' {
            $scope = Get-Scope -StigId 'IIS_10-0_Server'

            $scope.Loop | Should-BeFalsy
            $scope.RoleVariable | Should-BeFalsy
        }
    }

    # A site STIG describes a hardened website, not one chosen site, so its rules configure every
    # site the role names.
    Context 'anything else' {

        It 'points the path at the site the loop is on' {
            (Get-Scope -StigId 'IIS_10-0_Site').Path | Should-Be 'IIS:\Sites\{{ item }}'
        }

        It 'loops the role''s website list' {
            (Get-Scope -StigId 'IIS_10-0_Site').Loop | Should-Be '{{ stig_iissite_10_0_websites }}'
        }

        It 'names the role variable that list comes from' {
            (Get-Scope -StigId 'IIS_10-0_Site').RoleVariable | Should-Be 'websites'
        }
    }
}
