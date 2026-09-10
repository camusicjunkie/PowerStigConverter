function Export-AnsibleTaskBySeverity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Task
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
        if ($high.Count -gt 0) { ($high.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray }) |
            Out-File -FilePath $PSScriptRoot\Roles\cat1.yml -Append
        }
        if ($medium.Count -gt 0) { ($medium.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray }) |
            Out-File -FilePath $PSScriptRoot\Roles\cat2.yml -Append
        }
        if ($low.Count -gt 0) { ($low.Values | ForEach-Object { ConvertTo-Yaml $_ -KeepArray }) |
            Out-File -FilePath $PSScriptRoot\Roles\cat3.yml -Append
        }
    }
}
