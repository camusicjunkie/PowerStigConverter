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
    }
    process {
        $ruleName = $InputObject.PowerStigRule -replace 'Rule'
        $stigRule = $InputObject.StigRule

        # A rule type is supported exactly when it has an adapter, so that is the question asked -
        # rather than calling a function named after it and reading the failure.
        if (Get-Command "Build-Ansible$($ruleName)Task" -ErrorAction Ignore) {
            Write-Verbose "Build-Ansible$($ruleName)Task is being processed."
            $stigRule | ConvertTo-AnsibleTask -RuleType $ruleName @natParams
        }
        else {
            Write-Warning "Build-Ansible$($ruleName)Task is not currently supported."
        }
    }
}
