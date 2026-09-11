function ConvertTo-AnsiblePlaybook {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [string] $StigName,

        [hashtable] $OrgSetting,

        [string] $StigId
    )

    begin {
        $natParams = @{
            StigName = $StigName
            OrgSetting = $OrgSetting
            ErrorAction = 'Stop'
        }
    }
    process {
        $dscResourceModule = $InputObject.DscResourceModule
        $ruleName = $InputObject.PowerStigRule -replace 'Rule'
        $stigRule = $InputObject.StigRule

        if ($dscResourceModule -like '*WebAdministration*') { $natParams.Add('StigId', $stigId) }

        try {
            Write-Verbose "New-Ansible$($ruleName)Task is being processed."
            $stigRule | & "New-Ansible$($ruleName)Task" @natParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "New-Ansible$($ruleName)Task is not currently supported."
        }

        $natParams.Remove('StigId')
    }
}
