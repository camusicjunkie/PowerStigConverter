function ConvertTo-AnsiblePlaybook {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{},

        [string] $StigId
    )

    begin {
        # Every adapter takes -StigId; the two that configure IIS read it and the rest ignore it,
        # so there is nothing to decide. This used to be granted by matching the rule's dsc module
        # against *WebAdministration*, which was rule data standing in for a parameter set. See #17.
        $natParams = @{
            StigName = $StigName
            OrganizationalSetting = $OrganizationalSetting
            StigId = $StigId
            ErrorAction = 'Stop'
        }

        # The conversion's own OsFamily, read once - an adapter built for a different one is
        # skipped below rather than asked to build a task for a host it was never meant for.
        # See docs/adr/0010.
        $osFamily = (Get-AnsibleOsAssertion -StigName $StigName).OsFamily
    }
    process {
        $ruleName = $InputObject.PowerStigRule -replace 'Rule'
        $stigRule = $InputObject.StigRule

        # A rule type is supported exactly when it has an adapter, so that is the question asked -
        # rather than calling a function named after it and reading the failure.
        if (-not (Get-Command "Build-Ansible$($ruleName)Task" -ErrorAction Ignore)) {
            Write-Warning "Build-Ansible$($ruleName)Task is not currently supported."
            return
        }

        # A rule type missing from the table is not restricted to any OsFamily - the coverage
        # test keeps every adapter listed, not this check. See docs/adr/0010.
        $adapterOsFamily = $script:ruleTypeOsFamily[$ruleName]
        if ($adapterOsFamily -and $adapterOsFamily -ne $osFamily) {
            $ids = ($stigRule.Id) -join ', '
            Write-Warning ('{0}: Build-Ansible{1}Task targets {2}, not {3} - skipping. See docs/adr/0010.' -f $ids, $ruleName, $adapterOsFamily, $osFamily)
            return
        }

        Write-Verbose "Build-Ansible$($ruleName)Task is being processed."
        $stigRule | ConvertTo-AnsibleTask -RuleType $ruleName @natParams
    }
}
