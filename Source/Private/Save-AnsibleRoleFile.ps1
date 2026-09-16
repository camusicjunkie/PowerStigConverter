function Save-AnsibleRoleFile {
    [CmdletBinding()]
    param (
        # File base name -> content. Each entry is written as <name>.yml under OutputPath,
        # replacing any previous run. Entries with no content are skipped rather than
        # written empty.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Content,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    foreach ($file in $Content.GetEnumerator()) {
        # @($null) counts as one element, so test the value before wrapping it
        if ($null -eq $file.Value) { continue }

        $lines = @($file.Value)
        if ($lines.Count -eq 0) { continue }

        # Written through .NET rather than Set-Content because -Encoding utf8 does not mean the
        # same thing on both engines: Windows PowerShell 5.1 writes a BOM, PowerShell 7 does not,
        # and -Encoding utf8NoBOM is 6.0+ so it cannot spell the difference away. A BOM in a role
        # file is a needless diff between two machines converting the same STIG.
        $text = ($lines -join [System.Environment]::NewLine) + [System.Environment]::NewLine
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $OutputPath "$($file.Key).yml"), $text, $utf8NoBom)
    }
}
