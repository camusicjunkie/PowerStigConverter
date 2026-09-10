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
        $severityFiles = @{
            main_default_cat1 = $high
            main_default_cat2 = $medium
            main_default_cat3 = $low
        }

        foreach ($severityFile in $severityFiles.GetEnumerator()) {
            if ($severityFile.Value.Count -eq 0) { continue }

            $severityFile.Value.Values |
                Set-Content -Path (Join-Path $OutputPath "$($severityFile.Key).yml") -Encoding utf8
        }
    }
}
