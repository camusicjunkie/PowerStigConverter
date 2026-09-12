<#
.SYNOPSIS
    The cases every task generator test has to cover, so a rule type cannot arrive thinly tested.
.DESCRIPTION
    Dot-source at file scope for discovery and in BeforeAll for run time; the rule factory
    reaches each It through -ForEach.

    The checklist, and where each item lives:

      1. the ansible module or DSC resource it emits      here
      2. the fields it maps off the rule                  each test file, it is per rule type
      3. guards the task with the conditional toggle      here
      4. skips a rule that duplicates another             here
      5. idempotent over the same rule object             here
      6. a single-valued list stays a list                each test file, rule types with a
                                                          List key in OrganizationData.psd1
      7. an organization value reaches the task as a      each test file, the generators that
         reference rather than a literal                  call Resolve-AnsibleOrganizationValue

    GeneratorCoverage.Tests.ps1 enforces all of it.
#>

<#
.SYNOPSIS
    Adds the shared contract cases to the calling Describe.
.PARAMETER Factory
    Builds a fresh rule, so a mutation in one case cannot reach another.
.PARAMETER Module
    The ansible module or DSC resource key the task is expected to carry. Looked for anywhere in
    the emitted task, because five generators nest the real task inside a block.
.PARAMETER ExtraParams
    Anything beyond -StigName the generator needs, e.g. @{ StigId = 'IIS_10-0_Server' }.
#>
function Add-GeneratorContractTests {
    param (
        [Parameter(Mandatory)] [string] $Generator,
        [Parameter(Mandatory)] [scriptblock] $Factory,
        [Parameter(Mandatory)] [string] $Module,
        [string] $StigName = 'WindowsServer-2022-MS',
        [hashtable] $ExtraParams = @{}
    )

    $case = @(@{
        Generator = $Generator
        Factory = $Factory
        Module = $Module
        StigName = $StigName
        ExtraParams = $ExtraParams
    })

    Context 'the generator contract' {

        It 'emits <Module>' -ForEach $case {
            $item = Invoke-Generator -Generator $Generator -Rule (& $Factory) -StigName $StigName -ExtraParams $ExtraParams

            $item | Should-NotBeNull
            Test-TaskCarriesModule -Task $item.Task -Module $Module | Should-BeTrue
        }

        # Without it the rule applies unconditionally. Sits on whatever task reaches the
        # severity file - for a grouped type, the block.
        It 'guards the task with the conditional toggle for the rule' -ForEach $case {
            $item = Invoke-Generator -Generator $Generator -Rule (& $Factory) -StigName $StigName -ExtraParams $ExtraParams

            $item.Task.when | Should-BeLikeString '*_when'
        }

        # A duplicate is covered by the rule it points at, so it must produce no task at all -
        # not an empty one, and not a toggle in defaults/ guarding nothing.
        It 'skips a rule that duplicates another' -ForEach $case {
            $rule = & $Factory
            $rule.DuplicateOf = 'V-099'

            $item = Invoke-Generator -Generator $Generator -Rule $rule -StigName $StigName -ExtraParams $ExtraParams

            @($item).Count | Should-Be 0
        }

        # Two generators used to write back to the rule; ADR-0003 deleted both.
        It 'leaves the rule it was given unchanged' -ForEach $case {
            $rule = & $Factory
            $before = $rule | ConvertTo-Json -Depth 6 -Compress

            $null = Invoke-Generator -Generator $Generator -Rule $rule -StigName $StigName -ExtraParams $ExtraParams

            $rule | ConvertTo-Json -Depth 6 -Compress | Should-Be $before
        }

        It 'builds the same task the second time' -ForEach $case {
            $rule = & $Factory

            $first = Invoke-Generator -Generator $Generator -Rule $rule -StigName $StigName -ExtraParams $ExtraParams
            $second = Invoke-Generator -Generator $Generator -Rule $rule -StigName $StigName -ExtraParams $ExtraParams

            $second.Task | ConvertTo-Json -Depth 12 -Compress |
                Should-Be ($first.Task | ConvertTo-Json -Depth 12 -Compress)
        }
    }
}

<#
.SYNOPSIS
    Runs one generator over one rule inside the module, and hands back the item it emitted.
#>
function Invoke-Generator {
    param ($Generator, $Rule, $StigName, $ExtraParams = @{}, $OrganizationalSetting = @{})

    InModuleScope -ModuleName PowerStigConverter -Parameters @{
        Generator = $Generator; Rule = $Rule; StigName = $StigName
        ExtraParams = $ExtraParams; OrganizationalSetting = $OrganizationalSetting
    } {
        param ($Generator, $Rule, $StigName, $ExtraParams, $OrganizationalSetting)

        $params = @{ StigName = $StigName; OrganizationalSetting = $OrganizationalSetting } + $ExtraParams

        # A rule type with an adapter is driven through the shared module; the rest still carry
        # their own plumbing. The one place that knows the difference.
        if ($Generator -like 'Build-*') {
            $Rule | ConvertTo-AnsibleTask -RuleType ($Generator -replace '^Build-Ansible' -replace 'Task$') @params
        }
        else {
            $Rule | & $Generator @params
        }
    }
}

<#
.SYNOPSIS
    True when the module key appears on the task or on any task nested in its block.
.DESCRIPTION
    Five rule types collapse their tasks into a block, and Service and RootCertificate wrap theirs
    alongside a register and an assert, so the key the caller cares about is rarely on the outer
    task. Searching the tree keeps the contract's interface to one module name.
#>
function Test-TaskCarriesModule {
    param ($Task, [string] $Module)

    if ($null -eq $Task) { return $false }

    foreach ($key in @($Task.Keys)) {
        if ($key -eq $Module) { return $true }
    }

    foreach ($nested in @($Task.block)) {
        if (Test-TaskCarriesModule -Task $nested -Module $Module) { return $true }
    }

    return $false
}

<#
.SYNOPSIS
    Builds an org settings map from inline xml, the way Get-PowerStigOrgSetting does.
.DESCRIPTION
    The same helper Initialize-TestModule.ps1 defines, repeated here because a generator test
    dot-sources this file at discovery time and that one only at run time.
#>
function New-ContractOrgSetting {
    param ([string] $Xml)

    [xml] $document = "<OrganizationalSettings>$Xml</OrganizationalSettings>"

    $settings = @{}
    foreach ($node in $document.OrganizationalSettings.OrganizationalSetting) {
        $settings[$node.id] = $node
    }
    $settings
}
