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

        # A rule type with an adapter goes through the shared module; the rest still carry their
        # own plumbing. Both are looked up by name, and neither existing is what "not supported"
        # means.
        try {
            if (Get-Command "Build-Ansible$($ruleName)Task" -ErrorAction Ignore) {
                Write-Verbose "Build-Ansible$($ruleName)Task is being processed."
                $stigRule | ConvertTo-AnsibleTask -RuleType $ruleName @natParams
            }
            else {
                Write-Verbose "New-Ansible$($ruleName)Task is being processed."
                $stigRule | & "New-Ansible$($ruleName)Task" @natParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "New-Ansible$($ruleName)Task is not currently supported."
        }

        $natParams.Remove('StigId')
    }
}
