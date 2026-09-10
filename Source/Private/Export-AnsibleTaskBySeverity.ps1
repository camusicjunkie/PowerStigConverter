function Export-AnsibleTaskBySeverity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Task,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        $null = $items.Add(@{
            Id = $Task.Rule.Id
            Severity = $Task.Rule.Severity
            Value = $Task.Task
        })
    }
    end {
        $bySeverity = Group-AnsibleRuleBySeverity -InputObject $items.ToArray()

        Save-AnsibleRoleFile -OutputPath $OutputPath -Content ([ordered] @{
            cat1 = $bySeverity.high.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray }
            cat2 = $bySeverity.medium.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray }
            cat3 = $bySeverity.low.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray }
        })
    }
}
