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
        $natParams = @{
            StigName = $StigName
            OrganizationalSetting = $OrganizationalSetting
            ErrorAction = 'Stop'
        }
    }
    process {
        $dscResourceModule = $InputObject.DscResourceModule
        $ruleName = $InputObject.PowerStigRule -replace 'Rule'
        $stigRule = $InputObject.StigRule

        if ($dscResourceModule -like '*WebAdministration*') { $natParams.Add('StigId', $stigId) }

        # A rule type is supported exactly when it has an adapter, so that is the question asked -
        # rather than calling a function named after it and reading the failure.
        if (Get-Command "Build-Ansible$($ruleName)Task" -ErrorAction Ignore) {
            Write-Verbose "Build-Ansible$($ruleName)Task is being processed."
            $stigRule | ConvertTo-AnsibleTask -RuleType $ruleName @natParams
        }
        else {
            Write-Warning "Build-Ansible$($ruleName)Task is not currently supported."
        }

        $natParams.Remove('StigId')
    }
}
