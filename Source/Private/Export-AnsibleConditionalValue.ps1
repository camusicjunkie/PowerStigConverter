function Export-AnsibleConditionalValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [string] $StigName,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        foreach ($rule in $InputObject.StigRule) {
            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ StigName = $StigName }
            $navParams.TaskId = if ($rule.Id -match '\.[a-z]$') { $baseId } else { $rule.Id }

            $null = $items.Add(@{
                Id = $baseId
                Severity = $rule.Severity
                Value = New-AnsibleVariable @navParams -Type ConditionalValue
            })
        }
    }
    end {
        $bySeverity = Group-AnsibleRuleBySeverity -InputObject $items.ToArray()

        Save-AnsibleRoleFile -OutputPath $OutputPath -Content ([ordered] @{
            main_default_cat1 = $bySeverity.high.Values
            main_default_cat2 = $bySeverity.medium.Values
            main_default_cat3 = $bySeverity.low.Values
        })
    }
}
