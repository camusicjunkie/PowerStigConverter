function Resolve-AnsibleOrganizationValue {
    <#
    .SYNOPSIS
        Everything the conversion needs to know about one rule's organization values.
    .DESCRIPTION
        Takes the four things every organization value question needs, once, and answers all of
        them. The rule is never written to, so it can be resolved repeatedly. See docs/adr/0004.

            Value       what the task consumes - a literal, or a variable reference
            Variable    one organization variable per part the task needs
            Incomplete  the variables the org settings file does not answer
            Assert      the assert guarding those, or nothing
    .OUTPUTS
        A single object carrying Value, Variable, Incomplete and Assert.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object] $Rule,

        # Validated against OrganizationData.psd1's keys, not a copied list.
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

    # Flat rather than a mapping, so one field can be overridden with -e. See docs/adr/0003.
    $variables = @(
        if ($decidedByOrganization) {
            foreach ($field in $data['Required']) {

                # Missing and unanswered differ because the remedies do: fetch a matching org
                # settings file, versus fill the value in. Judged per field, so parts agree.
                $status = if ($null -eq $node) { 'Missing' }
                    elseif ([string]::IsNullOrWhiteSpace($node.$field)) { 'Unanswered' }
                    else { 'Answered' }

                # One field is one variable, unless OrganizationData.psd1 says it answers more
                # than one module parameter.
                $parts = if ($null -ne $data['Part'] -and $data['Part'].ContainsKey($field)) {
                    $data['Part'][$field]
                }
                else {
                    @($field)
                }

                foreach ($part in $parts) {
                    # A type with a Name property names the variable after it; the rest after
                    # the part.
                    $taskName = if ([string]::IsNullOrEmpty($data['Name'])) { $part } else { $Rule.($data['Name']) }

                    # Reshaped here, not on the host, so a test can see it - docs/adr/0003. No
                    # default when unanswered: that declares the variable blank to fill in. The
                    # unary comma is load-bearing - without it a one-element split unrolls to a
                    # string and is written as a scalar rather than a sequence.
                    $default = if ($status -ne 'Answered') { $null }
                        elseif ($part -eq 'store_name') { Split-Path -Path $node.$field -Leaf }
                        elseif ($part -eq 'store_location') { Split-Path -Path (Split-Path -Path $node.$field -Parent) -Leaf }
                        elseif ($data['List'] -contains $field) { , ($node.$field -split ',') }
                        else { $node.$field }

                    $navParams = @{ TaskId = $Rule.Id; TaskName = $taskName; StigName = $StigName }

                    [pscustomobject] @{
                        RuleId = $Rule.Id
                        RuleType = $RuleType
                        Field = $field  # the org settings attribute it came from
                        Part = $part   # which of that field's values this variable holds
                        Status = $status
                        # Declaration, reference and assert all build on this one name.
                        Name = New-AnsibleVariable @navParams -Type OrganizationName
                        Reference = New-AnsibleVariable @navParams -Type Organization
                        Default = $default
                        Declaration = New-AnsibleVariable @navParams -NodeValue $default -Type OrganizationValue
                    }
                }
            }
        }
    )

    # A duplicate produces no task, so an unanswered value behind it guards nothing.
    $incomplete = @(if (-not $duplicate) { $variables.Where({ $_.Status -ne 'Answered' }) })

    # Keyed by part; for most rule types the part is the field.
    $reference = @{}
    foreach ($variable in $variables) { $reference[$variable.Part] = $variable.Reference }

    $value = if ($decidedByOrganization) {

        # An organization value never reaches the task as a literal. See docs/adr/0003.
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
                    # Nested rather than scalar, and optional, so it stays built in place.
                    LogCustomFields = $node.LogCustomFieldEntry
                }
            }
            'RootCertificate' {
                [pscustomobject] @{
                    StoreName = $reference['store_name']
                    StoreLocation = $reference['store_location']
                }
            }
            default { $reference[$data['Value']] }
        }
    }
    # Same shape whichever way the value arrived. Rare: these rules are org-valued in practice.
    elseif ($RuleType -eq 'RootCertificate') {
        [pscustomobject] @{
            StoreName = Split-Path -Path $Rule.Location -Leaf
            StoreLocation = Split-Path -Path (Split-Path -Path $Rule.Location -Parent) -Leaf
        }
    }
    elseif ($Rule.($data['Value']) -match 'Enabled|Disabled') {

        $option = $script:accountPolicyData + $script:securityOptionData
        $attributeName = $Rule.($data['Name']) -replace '/|\s', '_' -replace ':'
        # Keyed by the value asked for, not the property name - indexing by the name misses
        # every time and the cast then turns every rule into 0.
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
            LogFlags = if ($Rule.LogFlags) { , ($Rule.LogFlags -split ',') }
            LogFormat = $Rule.LogFormat
            LogPeriod = $Rule.LogPeriod
            LogTarget = if ($Rule.LogTargetW3C) { , ($Rule.LogTargetW3C -split ',') }
            LogCustomFields = $Rule.LogCustomFieldEntry
        }
    }
    # Split here so both halves hand back the same shape; the comma keeps one element an array.
    elseif ($data['List'] -contains $data['Value']) {
        , ($Rule.($data['Value']) -split ',')
    }
    else { $Rule.($data['Value']) }

    # Only unanswered settings get one, so a role's asserts are its open questions. This is what
    # -AllowIncompleteOrganizationValue produces. See docs/adr/0003.
    $assert = if ($incomplete.Count -gt 0) {
        [ordered] @{
            'name' = 'Assert the organization values for {0} have been filled in' -f $Rule.Id
            'ansible.builtin.assert' = [ordered] @{
                # default() so an undefined variable fails the assert, not the play.
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
