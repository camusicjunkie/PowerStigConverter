function Get-PowerStigFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Name', 'Org')]
        [string] $Type,

        [switch] $Previous
    )

    $soParams = if ($Previous) { @{ Last = 1 } } else { @{ First = 1 } }
    $stigFiles = switch ($Type) {
        'Name' {
            Get-ChildItem -Path $env:LOCALAPPDATA\PowerStig\source\StigData\Processed -Exclude '*.org.default.xml'; break
        }
        'Org' {
            Get-ChildItem -Path $env:LOCALAPPDATA\PowerStig\source\StigData\Processed -Include '*.org.default.xml' -Recurse; break
        }
    }

    $matchedStigFiles = $stigFiles | ForEach-Object {
        if ($_.Name -match '^(.+)-([\d.]+)(\.org\.default)?\.xml$') {
            [pscustomobject] @{
                Name = $matches[1]
                Version = [version] $matches[2]
                FullName = $_
            }
        }
    }
    $matchedStigFiles | Group-Object Name | ForEach-Object {
        $_.Group | Sort-Object -Property Version -Descending | Select-Object @soParams
    } | Select-Object -ExpandProperty FullName
}
