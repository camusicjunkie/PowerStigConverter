function Export-AnsibleConditionalValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [string] $StigName
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        # One generated task, one toggle. Sub-rules (V-254343.b) were already collapsed into a
        # single block task guarded by the base id, so the toggle is named for the base id too.
        $rule = $InputObject.Rule
        $baseId = Get-PowerStigBaseRuleId -Id $rule.Id

        $null = $items.Add(@{
            Id = $baseId
            Severity = $rule.Severity
            Value = New-AnsibleToggleLine -TaskId $baseId -StigName $StigName
        })
    }
    end {
        $bySeverity = Group-AnsibleRuleBySeverity -InputObject $items.ToArray()

        [ordered] @{
            main_default_cat1 = $bySeverity.high.Values
            main_default_cat2 = $bySeverity.medium.Values
            main_default_cat3 = $bySeverity.low.Values
        }
    }
}
