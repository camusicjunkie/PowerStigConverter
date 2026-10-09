function Save-AnsibleRoleFile {
    [CmdletBinding()]
    param (
        # File base name -> content. Each entry is written as <name>.yml under OutputPath,
        # replacing any previous run. An entry with no content throws (#135) and nothing is written.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Content,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    # Validate every entry first so a bad one cannot leave the role half-written.
    $files = foreach ($file in $Content.GetEnumerator()) {
        # @($null) counts as one element, so test the value before wrapping it
        $lines = if ($null -ne $file.Value) { @($file.Value) } else { @() }
        if ($lines.Count -eq 0) {
            throw "No content was generated for '$($file.Key).yml'; refusing to leave an earlier run's file in place."
        }
        [pscustomobject] @{ Name = $file.Key; Lines = $lines }
    }

    foreach ($file in $files) {
        # Written through .NET rather than Set-Content because -Encoding utf8 does not mean the
        # same thing on both engines: Windows PowerShell 5.1 writes a BOM, PowerShell 7 does not,
        # and -Encoding utf8NoBOM is 6.0+ so it cannot spell the difference away. A BOM in a role
        # file is a needless diff between two machines converting the same STIG.
        $text = ($file.Lines -join [System.Environment]::NewLine) + [System.Environment]::NewLine
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $OutputPath "$($file.Name).yml"), $text, $utf8NoBom)
    }
}
