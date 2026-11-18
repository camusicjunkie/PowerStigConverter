#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Get-Completion {
        param ([string] $WordToComplete)

        $splat = @{ CommandName = 'New-AnsiblePlaybook'; ParameterName = 'StigName'; WordToComplete = $WordToComplete }
        Invoke-PrivateCommand -Command 'Get-StigNameCompletion' -Splat $splat
    }
}

Describe 'Get-StigNameCompletion' {

    BeforeAll {
        Mock -ModuleName PowerStigConverter -CommandName Get-PowerStigFile -MockWith {
            'WindowsServer-2022-MS-1.2', 'WindowsServer-2022-MS-2.7', 'WindowsServer-2022-DC-1.0', 'MS-Edge-2.5' |
                ForEach-Object { [pscustomobject] @{ BaseName = $_ } }
        }
    }

    It 'offers each STIG once, without its revision' {
        (Get-Completion -WordToComplete '').CompletionText |
            Should-BeCollection @('MS-Edge', 'WindowsServer-2022-DC', 'WindowsServer-2022-MS')
    }

    It 'offers only the STIGs that start with what has been typed' {
        (Get-Completion -WordToComplete 'WindowsServer-2022-M').CompletionText |
            Should-BeCollection @('WindowsServer-2022-MS')
    }

    It 'returns completion results as parameter values' {
        $result = Get-Completion -WordToComplete 'MS'
        $result | Should-HaveType ([System.Management.Automation.CompletionResult])
        $result.ResultType | Should-Be ([System.Management.Automation.CompletionResultType]::ParameterValue)
    }

    It 'is what New-AnsiblePlaybook -StigName completes to' {
        $line = 'New-AnsiblePlaybook -StigName WindowsServer-2022-D'
        $completion = TabExpansion2 -inputScript $line -cursorColumn $line.Length

        $completion.CompletionMatches.CompletionText | Should-BeCollection @('WindowsServer-2022-DC')
    }
}
