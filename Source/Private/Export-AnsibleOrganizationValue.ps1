function Export-AnsibleOrganizationValue {
    [CmdletBinding()]
    param (
        # The converted tasks, carrying the defaults/ lines and role-scoped variables they need.
        # A rule the generators skipped has no task, so declares nothing. See docs/adr/0016.
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Task,

        [string] $StigName
    )

    begin {
        $organization = [System.Collections.SortedList]::new()
    }
    process {
        # Flat, one line per variable, so a field can be overridden with -e (docs/adr/0003). Role
        # variables come from the tasks, so a STIG referencing no website declares none (#57).
        foreach ($declaration in @(@($Task.Declaration) + @($Task.RoleVariable).Declaration)) {
            if ($declaration -and -not $organization.ContainsKey($declaration)) {
                $organization.Add($declaration, $declaration)
            }
        }
    }
    end {
        $content = @(@'
{0}_cat1: true
{0}_cat2: true
{0}_cat3: true

'@ -f (Get-AnsibleVariablePrefix -StigName $StigName))

        if ($organization.Count -gt 0) { $content += $organization.Values }

        [ordered] @{ main_default_org = $content }
    }
}
