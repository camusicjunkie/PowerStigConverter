function Export-AnsibleConditionalValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [string] $StigName
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        # One generated task, one toggle. Sub-rules (V-254343.b) were already collapsed into a
        # single block task guarded by the base id, so the toggle is named for the base id too.
        $rule = $InputObject.Rule
        $baseId = Get-PowerStigBaseRuleId -Id $rule.Id

        $null = $items.Add(@{
            Id = $baseId
            Severity = $rule.Severity
            Value = New-AnsibleToggleLine -TaskId $baseId -StigName $StigName
        })
    }
    end {
        $files = [ordered] @{}
        $severityToggles = foreach ($category in (Group-AnsibleBySeverity -InputObject $items.ToArray()).GetEnumerator()) {
            # Written even when empty, so a re-run cannot leave an earlier revision's toggles behind.
            # An empty mapping, as main_default_org.yml is. See #131.
            $toggles = $category.Value
            $content = if ($toggles.Item.Count -gt 0) { @($toggles.Item.Values) }
                else { @(('# {0} has no {1} severity rules.' -f $StigName, $toggles.Severity), '{}') }
            $files['main_default_{0}' -f $category.Key] = $content
            # tasks/main.yml guards each severity file's import on one, so all three are declared
            # whatever the STIG carries. See #130.
            New-AnsibleSeverityToggleLine -Category $category.Key -StigName $StigName
        }
        $files['main_default_severity'] = @($severityToggles)
        $files
    }
}
