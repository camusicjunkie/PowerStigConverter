function Build-AnsibleAuditSettingTask {
    <#
    .SYNOPSIS
        Run the rule's WMI query and assert no instance fails its comparison.
    .DESCRIPTION
        Compared as AuditSystemDsc does - desired value on the left, both sides strings - since
        PowerStig's data is written for that order. Not through win_dsc: see docs/adr/0024.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    # Fixed text, so every rule carries the same script; the rule reaches it only as parameters.
    $script = @(
        '[CmdletBinding(SupportsShouldProcess)]'
        'param ([string] $Query, [string] $Property, [string] $Operator, [string] $DesiredValue, [string] $Namespace)'
        '$Ansible.Changed = $false'
        '$cim = @{ Query = $Query; ErrorAction = "Stop" }'
        'if ($Namespace) { $cim.Namespace = $Namespace }'
        'foreach ($instance in @(Get-CimInstance @cim)) {'
        '    $actual = [string] $instance.$Property'
        '    $pass = switch -Exact ($Operator) {'
        '        "-eq" { $DesiredValue -eq $actual }'
        '        "-ne" { $DesiredValue -ne $actual }'
        '        "-match" { $DesiredValue -match $actual }'
        '        "-notmatch" { $DesiredValue -notmatch $actual }'
        '        "-like" { $DesiredValue -like $actual }'
        '        "-notlike" { $DesiredValue -notlike $actual }'
        '        "-lt" { $DesiredValue -lt $actual }'
        '        "-le" { $DesiredValue -le $actual }'
        '        "-gt" { $DesiredValue -gt $actual }'
        '        "-ge" { $DesiredValue -ge $actual }'
        '        default { throw "Unsupported operator ''$Operator''" }'
        '    }'
        '    if (-not $pass) { $actual }'
        '}'
    ) -join "`n"

    $parameters = [ordered] @{
        'Query' = $Rule.Query
        'Property' = $Rule.Property
        'Operator' = $Rule.Operator
        'DesiredValue' = $Rule.DesiredValue
    }

    # Get-CimInstance defaults the namespace itself, so sending an empty one is worse than none.
    if ($Rule.Namespace) { $parameters.Namespace = $Rule.Namespace }

    $comparison = '{0} {1} {2}' -f $Rule.DesiredValue, $Rule.Operator, $Rule.Property
    $registerName = Get-AnsibleRegisterName -TaskId $Rule.Id -StigName $StigName -Suffix 'noncompliant'

    @{
        GroupDetail = 'Audit {0}' -f $comparison
        Task = @(
            @{
                Name = 'Gather {0}' -f $comparison
                Body = [ordered] @{
                    'ansible.windows.win_powershell' = [ordered] @{
                        'script' = $script
                        'parameters' = $parameters
                    }
                    'register' = $registerName
                }
            }
            @{
                Name = 'Assert {0}' -f $comparison
                Body = [ordered] @{
                    'ansible.builtin.assert' = [ordered] @{
                        'that' = "$registerName.output | length == 0"
                        'fail_msg' = '{0} is false for {1}: {{{{ {2}.output | join('', '') }}}}' -f $comparison, $Rule.Property, $registerName
                    }
                }
            }
        )
    }
}
