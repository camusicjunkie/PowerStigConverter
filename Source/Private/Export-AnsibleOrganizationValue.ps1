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
        $roleVariable = [System.Collections.Generic.HashSet[string]]::new()
    }
    process {
        # One declaration per organization variable - flat rather than a mapping, so a single
        # field can be overridden with -e and an assert can name the one that is unanswered.
        # Sub-rules collapse onto the same variable when they share a field.
        foreach ($declaration in @($Task.Declaration)) {
            if ($declaration -and -not $organization.ContainsKey($declaration)) {
                $organization.Add($declaration, $declaration)
            }
        }

        # The role-scoped lists the tasks loop over, named by the generators that reference them:
        # a STIG whose rules reference no website declares none. See #57.
        foreach ($name in @($Task.RoleVariable)) {
            if ($name) { $null = $roleVariable.Add($name) }
        }
    }
    end {
        # Role-scoped, so it carries no rule id and is declared once however many rules read it -
        # an empty list for the site to fill in, guarded by the assert Export-AnsibleTaskBySeverity
        # prepends. Sorted in among the rest by the same SortedList.
        foreach ($taskName in $roleVariable) {
            $declaration = New-AnsibleRoleVariableLine -TaskName $taskName -StigName $StigName
            if (-not $organization.ContainsKey($declaration)) {
                $organization.Add($declaration, $declaration)
            }
        }

        $content = @(@'
{0}_cat1: true
{0}_cat2: true
{0}_cat3: true

'@ -f (Get-AnsibleVariablePrefix -StigName $StigName))

        if ($organization.Count -gt 0) { $content += $organization.Values }

        [ordered] @{ main_default_org = $content }
    }
}
