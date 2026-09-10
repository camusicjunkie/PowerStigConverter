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

        $lines | Set-Content -Path (Join-Path $OutputPath "$($file.Key).yml") -Encoding utf8
    }
}
