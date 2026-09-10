#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . $PSScriptRoot/Initialize-TestModule.ps1

    function Get-Flag {
        param ($Resource, $Inheritance)

        InModuleScope -ModuleName PowerStigConverter -Parameters @{ Resource = $Resource; Inheritance = $Inheritance } {
            param ($Resource, $Inheritance)
            Get-AnsibleInheritanceFlag -Resource $Resource -Inheritance $Inheritance
        }
    }
}

Describe 'Get-AnsibleInheritanceFlag' {

    # PowerStig states inheritance as the phrase the Windows ACL editor shows. win_acl wants
    # the .NET flags instead, so each phrase maps onto an InheritanceFlags / PropagationFlags
    # pair. The expected pairs below are the Windows ACL meanings of those phrases:
    # ContainerInherit propagates to subkeys and subfolders, ObjectInherit to files, and
    # InheritOnly withholds the entry from the object it is set on.
    Context 'file system permissions' {

        It 'maps "<Inheritance>" to <ExpectedInherit> / <ExpectedPropagation>' -ForEach @(
            @{ Inheritance = 'This folder only'; ExpectedInherit = 'None'; ExpectedPropagation = 'None' }
            @{ Inheritance = 'This folder subfolders and files'; ExpectedInherit = 'ContainerInherit, ObjectInherit'; ExpectedPropagation = 'None' }
            @{ Inheritance = 'This folder and subfolders'; ExpectedInherit = 'ContainerInherit'; ExpectedPropagation = 'None' }
            @{ Inheritance = 'This folder and files'; ExpectedInherit = 'ObjectInherit'; ExpectedPropagation = 'None' }
            @{ Inheritance = 'Subfolders and files only'; ExpectedInherit = 'ContainerInherit, ObjectInherit'; ExpectedPropagation = 'InheritOnly' }
            @{ Inheritance = 'Subfolders only'; ExpectedInherit = 'ContainerInherit'; ExpectedPropagation = 'InheritOnly' }
            @{ Inheritance = 'Files only'; ExpectedInherit = 'ObjectInherit'; ExpectedPropagation = 'InheritOnly' }
        ) {
            $flags = Get-Flag -Resource 'NTFSAccessEntry' -Inheritance $Inheritance

            $flags.InheritanceFlag.ToString() | Should-Be $ExpectedInherit
            $flags.PropagationFlag.ToString() | Should-Be $ExpectedPropagation
        }

        It 'falls back to this-folder-only for a phrase it does not recognise' {
            $flags = Get-Flag -Resource 'NTFSAccessEntry' -Inheritance 'something PowerStig has not emitted before'

            $flags.InheritanceFlag.ToString() | Should-Be 'None'
            $flags.PropagationFlag.ToString() | Should-Be 'None'
        }
    }

    Context 'registry permissions' {

        It 'maps "<Inheritance>" to <ExpectedInherit> / <ExpectedPropagation>' -ForEach @(
            @{ Inheritance = 'This Key Only'; ExpectedInherit = 'None'; ExpectedPropagation = 'None' }
            @{ Inheritance = 'This Key and Subkeys'; ExpectedInherit = 'ContainerInherit'; ExpectedPropagation = 'None' }
            @{ Inheritance = 'Subkeys Only'; ExpectedInherit = 'ContainerInherit'; ExpectedPropagation = 'InheritOnly' }
        ) {
            $flags = Get-Flag -Resource 'RegistryAccessEntry' -Inheritance $Inheritance

            $flags.InheritanceFlag.ToString() | Should-Be $ExpectedInherit
            $flags.PropagationFlag.ToString() | Should-Be $ExpectedPropagation
        }

        It 'falls back to key-and-subkeys for a phrase it does not recognise' {
            $flags = Get-Flag -Resource 'RegistryAccessEntry' -Inheritance 'something PowerStig has not emitted before'

            $flags.InheritanceFlag.ToString() | Should-Be 'ContainerInherit'
            $flags.PropagationFlag.ToString() | Should-Be 'None'
        }
    }

    Context 'a DSC resource with no mapping' {

        It 'returns no flags rather than guessing at them' {
            $flags = Get-Flag -Resource 'SomeOtherAccessEntry' -Inheritance 'This folder only'

            $flags.InheritanceFlag | Should-BeNull
            $flags.PropagationFlag | Should-BeNull
        }
    }
}
