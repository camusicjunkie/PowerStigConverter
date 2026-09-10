function Export-AnsibleConditionalValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [string] $StigName
    )

    begin {
        $high = [System.Collections.SortedList]::new()
        $medium = [System.Collections.SortedList]::new()
        $low = [System.Collections.SortedList]::new()
    }
    process {
        foreach ($rule in $InputObject.StigRule) {
            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ StigName = $StigName }
            $navParams.TaskId = if ($rule.Id -match '\.[a-z]$') { $baseId } else { $rule.Id }
            $conditionalVariable = New-AnsibleVariable @navParams -Type ConditionalValue

            switch ($rule.Severity) {
                'high' { if (-not $high.ContainsKey($baseId)) { $high.Add($baseId, $conditionalVariable) } }
                'medium' { if (-not $medium.ContainsKey($baseId)) { $medium.Add($baseId, $conditionalVariable) } }
                'low' { if (-not $low.ContainsKey($baseId)) { $low.Add($baseId, $conditionalVariable) } }
            }
        }
    }
    end {
        if ($high.Count -gt 0) { $high.Values | Out-File -FilePath $PSScriptRoot\Roles\main_default_cat1.yml -Append }
        if ($medium.Count -gt 0) { $medium.Values | Out-File -FilePath $PSScriptRoot\Roles\main_default_cat2.yml -Append }
        if ($low.Count -gt 0) { $low.Values | Out-File -FilePath $PSScriptRoot\Roles\main_default_cat3.yml -Append }
    }
}
