function Build-AnsibleSqlScriptQueryTask {
    <#
    .SYNOPSIS
        The rule's own Get/Test/Set T-SQL triad, through win_dsc, on every instance the role names.
    .DESCRIPTION
        One task per rule, carrying the three scripts verbatim - the rule states them, so nothing
        is authored here. InstanceName comes from the role-scoped list every Sql* generator shares;
        ServerName, credentials, QueryTimeout, DisableVariables and Encrypt are all omitted, each
        being a fact about the target rather than something the rule states.

        Id is a Key on SqlServerDsc 17.x and does not exist before it, so generated SQL roles
        require 17.x+. Upstream never uses the value, which leaves the rule id as the obvious
        rule-derived choice. See #65.

        No handler and no union: the rules that share a SetScript share it byte for byte, so the
        first whose Test fails satisfies them all and the rest skip.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $instances = Get-AnsibleRoleVariableReference -TaskName 'instances' -StigName $StigName

    $body = [ordered] @{
        'resource_name' = 'SqlScriptQuery'
        'Id' = $Rule.Id
        'InstanceName' = '{{ item }}'
        'GetQuery' = $Rule.GetScript
        'TestQuery' = $Rule.TestScript
        'SetQuery' = $Rule.SetScript
    }

    # The rule's Variable is a template holding the {0} the value goes into. No branch on whether
    # the organization decides it: .Value is the variable reference when it does and the rule's own
    # VariableValue when it does not. A rule that declares none binds nothing, and the property is
    # left off entirely, the way PowerStig's own composite does.
    if (-not [string]::IsNullOrEmpty($Rule.Variable)) {
        $body['Variable'] = @($Rule.Variable -f $Resolution.Value)
    }

    Write-AnsibleUnboundScriptVariableWarning -Rule $Rule

    @{
        RoleVariable = 'instances'
        Task = @(
            @{
                # SqlScriptQuery rules carry no field to name the requirement by - only the three
                # scripts and STIG prose written for a human auditor - so this says so plainly
                # rather than mining the prose. The id and severity already index the task.
                Detail = 'Ensure the SQL script requirement is met'
                Body = [ordered] @{
                    'ansible.windows.win_dsc' = $body
                    'loop' = $instances
                }
            }
        )
    }
}

<#
.SYNOPSIS
    Warns when a rule's SetScript leaves a blank its Variable does not fill in.
.DESCRIPTION
    $(name) is not T-SQL - Invoke-SqlCmd substitutes it before the script reaches SQL Server and
    aborts if nothing bound it. A rule wanting one needs to ship the note saying so; 2022's
    V-274445 ships the script without it, which is an upstream data defect.

    Converted literally regardless: repairing upstream's data is not this module's job, and
    skipping the rule would leave a silent hole in STIG coverage. The failure would otherwise hide
    until run time, and only on the instances that actually needed fixing. Read off the rule alone,
    so the generator still reads nothing else. See #65.
#>
function Write-AnsibleUnboundScriptVariableWarning {
    param ($Rule)

    # A template binds one name per comma-separated part, left of the =.
    $bound = @($Rule.Variable -split ',' | ForEach-Object { ($_ -split '=', 2)[0].Trim() })

    # Unique, so a name the script uses twice is still one warning.
    $used = @([regex]::Matches($Rule.SetScript, '\$\((\w+)\)').ForEach({ $_.Groups[1].Value }) | Sort-Object -Unique)

    foreach ($name in $used) {
        if ($bound -contains $name) { continue }

        Write-Warning ("{0}: the SetScript uses the scripting variable `$({1}), but the rule declares no value for it. The generated task will fail on any instance where it runs - report it upstream to PowerStig." -f $Rule.Id, $name)
    }
}
