#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Format-YamlScalar {
        param ($Value, [switch] $InSequence)

        Invoke-PrivateCommand -Command 'Format-AnsibleYamlScalar' -Splat @{ Value = $Value; InSequence = $InSequence }
    }
}

Describe 'Format-AnsibleYamlScalar' {

    Context 'a value that stands as a plain scalar' {

        It 'leaves <Value> alone' -ForEach @(
            @{ Value = 'Administrators' }
            @{ Value = 60 }
            @{ Value = 0 }
        ) {
            Format-YamlScalar -Value $Value | Should-Be $Value
        }
    }

    Context 'a value yaml would otherwise misread' {

        It 'quotes a value that <Reason>' -ForEach @(
            @{ Reason = 'contains a colon and a space'; Value = 'Warning: you are being watched'; Expected = "'Warning: you are being watched'" }
            @{ Reason = 'has leading whitespace'; Value = ' leading'; Expected = "' leading'" }
            @{ Reason = 'has trailing whitespace'; Value = 'trailing '; Expected = "'trailing '" }
            @{ Reason = 'opens with a yaml comment marker'; Value = '#not a comment'; Expected = "'#not a comment'" }
            @{ Reason = 'opens with a yaml anchor marker'; Value = '&anchor'; Expected = "'&anchor'" }
            @{ Reason = 'opens with a yaml alias marker'; Value = '*alias'; Expected = "'*alias'" }
            @{ Reason = 'opens with a yaml block scalar marker'; Value = '|block'; Expected = "'|block'" }
            @{ Reason = 'opens with a yaml folded scalar marker'; Value = '>folded'; Expected = "'>folded'" }
            @{ Reason = 'opens with a yaml tag marker'; Value = '!tag'; Expected = "'!tag'" }
            @{ Reason = 'opens with a percent directive marker'; Value = '%directive'; Expected = "'%directive'" }
            @{ Reason = 'opens with an at-sign'; Value = '@reserved'; Expected = "'@reserved'" }
            @{ Reason = 'opens with a backtick'; Value = '`reserved'; Expected = "'" + '`reserved' + "'" }
        ) {
            Format-YamlScalar -Value $Value | Should-Be $Expected
        }

        It 'doubles an embedded single quote so the quoting survives' {
            Format-YamlScalar -Value "Don't: really" | Should-Be "'Don''t: really'"
        }
    }

    Context 'a non-string value' {

        # The unsafe pattern only ever matches a string, so anything else - an int the caller
        # never quotes - passes through untouched even if it happens to look unsafe as text.
        It 'leaves a non-string value alone even when its stringified form looks unsafe' {
            Format-YamlScalar -Value 60 | Should-Be 60
        }
    }

    Context '-InSequence' {

        # Inside a flow sequence a comma or a closing bracket ends the element, so those need
        # quoting there even though a plain scalar can hold them outside one.
        It 'quotes a value that <Reason>' -ForEach @(
            @{ Reason = 'contains a comma'; Value = 'a,b'; Expected = "'a,b'" }
            @{ Reason = 'contains a closing bracket'; Value = 'a]b'; Expected = "'a]b'" }
        ) {
            Format-YamlScalar -Value $Value -InSequence | Should-Be $Expected
        }

        # A closing bracket at the start is covered by the general leading-marker set outside a
        # sequence too, but a comma is safe there - only inside a sequence does it end the element.
        It 'leaves a comma alone outside a sequence' {
            Format-YamlScalar -Value 'a,b' | Should-Be 'a,b'
        }

        It 'still quotes what the outer set quotes' {
            Format-YamlScalar -Value 'Warning: you are being watched' -InSequence |
                Should-Be "'Warning: you are being watched'"
        }
    }
}
