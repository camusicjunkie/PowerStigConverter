function Resolve-AnsibleOrganizationValue {
    <#
    .SYNOPSIS
        Everything the conversion needs to know about one rule's organization values.
    .DESCRIPTION
        Rule, rule type, STIG name and the org settings map are the four things every question
        about an organization value needs, so they are answered here once rather than re-asked
        of four functions in turn. A caller resolves a rule and then reads off whichever answer
        it wants:

            Value       what the task consumes - the rule's own value, or a reference to the
                        role variable when DISA left the value to the organization
            Variable    one organization variable per field the rule type's task needs, each
                        carrying the name, the jinja reference, the default value and whether
                        the org settings file answers it
            Incomplete  the subset of those variables the org settings file does not answer
            Assert      the assert guarding those, or nothing when there is nothing to guard

        OrganizationData.psd1 is read only from here, so which fields a rule type needs and what
        each one is called is one edit in one file rather than four.

        Nothing is read off the rule but its own properties, and the rule is never written to,
        so the same rule can be resolved as often as a caller likes.
    .OUTPUTS
        A single object carrying Value, Variable, Incomplete and Assert.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        # Must be a key of OrganizationData.psd1, which supplies the rule and org node property
        # names to read for that type. Validated against that file rather than against a copied
        # list, so adding a rule type is one edit.
        [Parameter(Mandatory)]
        [ValidateScript(
            { $script:organizationData.ContainsKey($_) },
            ErrorMessage = "'{0}' is not a rule type OrganizationData.psd1 describes."
        )]
        [string] $RuleType,

        [string] $StigName,

        # The org settings loaded once by Get-PowerStigOrgSetting, keyed by rule id.
        [hashtable] $OrganizationalSetting = @{}
    )

    $data = $script:organizationData[$RuleType]
    $node = $OrganizationalSetting[$Rule.Id]

    $decidedByOrganization = $Rule.OrganizationValueRequired -eq $true
    $duplicate = -not [string]::IsNullOrEmpty($Rule.DuplicateOf)

    # One organization variable per field the task consumes, flat rather than a mapping, so a
    # single field can be overridden with -e and an assert can name the one that is unanswered.
    $variables = @(
        if ($decidedByOrganization) {
            foreach ($field in $data['Required']) {
                # Rule types with a Name property - a policy name, a value name, the display name
                # of a user right - name the variable after it, because one such type carries a
                # single value and the rule's own word for it reads better than the org node's
                # attribute name. The types whose task needs several fields have no single such
                # name, so each variable is named for its field instead.
                $taskName = if ([string]::IsNullOrEmpty($data['Name'])) { $field } else { $Rule.($data['Name']) }

                # Two faults, because their remedies differ. A missing setting means the org
                # settings file carries no entry for the rule at all, which usually means it does
                # not match the STIG version in hand; the operator fetches the right file. An
                # unanswered setting means the entry is there and empty; the operator fills it in.
                $status = if ($null -eq $node) { 'Missing' }
                    elseif ([string]::IsNullOrWhiteSpace($node.$field)) { 'Unanswered' }
                    else { 'Answered' }

                # Usually the org settings attribute verbatim. Two types need the value reshaped
                # here rather than on the host, because the shape the ansible module consumes
                # should be decided where a test can see it - see docs/adr/0003: a field the task
                # needs as a list is split, so the variable holds a yaml sequence; and a
                # certificate store path is reduced to its leaf, because PowerStig holds
                # Cert:\LocalMachine\Root where win_certificate_info takes a store name of Root.
                #
                # An unanswered or missing setting has no default, which is what declares the
                # variable blank for the operator to fill in.
                $default = if ($status -ne 'Answered') { $null }
                    elseif ($RuleType -eq 'RootCertificate' -and $field -eq 'Location') { Split-Path -Path $node.$field -Leaf }
                    elseif ($data['List'] -contains $field) { [string[]] ($node.$field -split ',') }
                    else { $node.$field }

                $navParams = @{ TaskId = $Rule.Id; TaskName = $taskName; StigName = $StigName }

                [pscustomobject] @{
                    RuleId = $Rule.Id
                    RuleType = $RuleType
                    Field = $field
                    Status = $status
                    # The declaration in defaults/, the reference the task interpolates and the
                    # assert that guards it must all name the same variable. They are all built
                    # from this one name so they cannot drift apart.
                    Name = New-AnsibleVariable @navParams -Type OrganizationName
                    Reference = New-AnsibleVariable @navParams -Type Organization
                    Default = $default
                    Declaration = New-AnsibleVariable @navParams -NodeValue $default -Type OrganizationValue
                }
            }
        }
    )

    # A duplicate produces no task, so an unanswered value behind it guards nothing and refusing
    # the conversion over it would refuse a role that had everything it needed. The variables
    # themselves are still resolved, so a caller that does reach one still gets its reference.
    $incomplete = @(if (-not $duplicate) { $variables.Where({ $_.Status -ne 'Answered' }) })

    $reference = @{}
    foreach ($variable in $variables) { $reference[$variable.Field] = $variable.Reference }

    $value = if ($decidedByOrganization) {

        # A value the organization decides never reaches the task as a literal. It is declared in
        # defaults/ and the task interpolates it, so the operator can answer the question by
        # editing one file instead of regenerating the role - and so an assert can check at run
        # time that it was answered at all. See docs/adr/0003.
        switch ($RuleType) {
            'Service' {
                [pscustomobject] @{
                    ServiceName = $reference['ServiceName']
                    StartupType = $reference['StartupType']
                }
            }
            'IisLogging' {
                [pscustomobject] @{
                    LogFlags = $reference['LogFlags']
                    LogFormat = $reference['LogFormat']
                    LogPeriod = $reference['LogPeriod']
                    LogTarget = $reference['LogTargetW3C']
                    # LogCustomFields is a nested structure rather than a scalar, and it is the
                    # one field marked optional, so nothing asserts on it and it stays built in
                    # place.
                    LogCustomFields = $node.LogCustomFieldEntry
                }
            }
            default { $reference[$data['Value']] }
        }
    }
    elseif ($Rule.($data['Value']) -match 'Enabled|Disabled') {

        $option = $script:accountPolicyData + $script:securityOptionData
        $attributeName = $Rule.($data['Name']) -replace '/|\s', '_' -replace ':'
        # The Option table is keyed by the value the rule asks for - Enabled, Disabled - so it
        # has to be indexed by that value, not by the name of the property the value was read
        # from. Indexing by the property name misses every time, and [int] $null then turns every
        # one of these rules into 0.
        [int] $option[$attributeName]['Option'][$Rule.($data['Value'])]
    }
    elseif ($data['Value'] -eq 'Identity' -and $Rule.Identity -eq 'NULL') { @() }
    elseif ($RuleType -eq 'Service') {
        [pscustomobject] @{
            ServiceName = $Rule.ServiceName
            StartupType = $Rule.StartupType
        }
    }
    elseif ($RuleType -eq 'IisLogging') {
        [pscustomobject] @{
            LogFlags = if ($Rule.LogFlags) { [string[]] ($Rule.LogFlags -split ',') }
            LogFormat = $Rule.LogFormat
            LogPeriod = $Rule.LogPeriod
            LogTarget = if ($Rule.LogTargetW3C) { [string[]] ($Rule.LogTargetW3C -split ',') }
            LogCustomFields = $Rule.LogCustomFieldEntry
        }
    }
    # A field the task needs as a list is split here rather than in the generator, so that both
    # halves of this hand back the same shape.
    elseif ($data['List'] -contains $data['Value']) {
        [string[]] ($Rule.($data['Value']) -split ',')
    }
    else { $Rule.($data['Value']) }

    # Only settings unanswered at generation time get an assert, so the asserts in a role double
    # as the list of questions nobody answered, and they disappear when it is regenerated against
    # a filled-in org settings file. New-AnsiblePlaybook normally refuses to generate at all in
    # that case; this is what -AllowIncompleteOrganizationValue produces instead, so that a role
    # generated over a part-filled org settings file fails loudly on the host rather than quietly
    # setting an empty value. See docs/adr/0003.
    $assert = if ($incomplete.Count -gt 0) {
        [ordered] @{
            'name' = 'Assert the organization values for {0} have been filled in' -f $Rule.Id
            'ansible.builtin.assert' = [ordered] @{
                # default("", true) so an undefined variable fails the assert rather than the play.
                'that' = @($incomplete.Name | ForEach-Object { '{0} | default("", true) | length > 0' -f $_ })
                'fail_msg' = '{0} needs {1} set in defaults/main/main_default_org.yml - PowerStig leaves this value for the organization to decide.' -f $Rule.Id, ($incomplete.Name -join ', ')
            }
        }
    }

    [pscustomobject] @{
        RuleId = $Rule.Id
        RuleType = $RuleType
        Value = $value
        Variable = $variables
        Incomplete = $incomplete
        Assert = $assert
    }
}
