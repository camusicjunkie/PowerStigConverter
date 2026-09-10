function Export-AnsibleTaskBySeverity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Task,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    begin {
        $high = [System.Collections.SortedList]::new()
        $medium = [System.Collections.SortedList]::new()
        $low = [System.Collections.SortedList]::new()
    }
    process {
        switch ($Task.Rule.Severity) {
            'high' { if (-not $high.ContainsKey($Task.Rule.Id)) { $high.Add($Task.Rule.Id, $Task.Task) } }
            'medium' { if (-not $medium.ContainsKey($Task.Rule.Id)) { $medium.Add($Task.Rule.Id, $Task.Task) } }
            'low' { if (-not $low.ContainsKey($Task.Rule.Id)) { $low.Add($Task.Rule.Id, $Task.Task) } }
        }
    }
    end {
        $severityFiles = @{
            cat1 = $high
            cat2 = $medium
            cat3 = $low
        }

        foreach ($severityFile in $severityFiles.GetEnumerator()) {
            if ($severityFile.Value.Count -eq 0) { continue }

            $severityFile.Value.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray } |
                Set-Content -Path (Join-Path $OutputPath "$($severityFile.Key).yml") -Encoding utf8
        }
    }
}
