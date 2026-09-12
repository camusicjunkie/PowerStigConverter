#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    $script:stig = 'IISServer-10.0'
    $script:splat = @{ StigId = 'IIS_10-0_Server'; MachinePath = 'MACHINE/WEBROOT/APPHOST'; TaskId = 'V-310'; StigName = $stig }
}

Describe 'Get-AnsibleIisScopePath' {

    Context 'a server STIG' {

        It 'returns the machine-wide path the caller supplied' {
            Invoke-PrivateCommand -Command 'Get-AnsibleIisScopePath' -Splat $splat |
                Should-Be 'MACHINE/WEBROOT/APPHOST'
        }
    }

    Context 'anything else' {

        It 'interpolates a website variable for the rule' {
            $siteSplat = $splat.Clone()
            $siteSplat.StigId = 'IIS_10-0_Site'

            Invoke-PrivateCommand -Command 'Get-AnsibleIisScopePath' -Splat $siteSplat |
                Should-Be 'IIS:\Sites\{{ stig_iisserver_10_0_310_website }}'
        }
    }
}
