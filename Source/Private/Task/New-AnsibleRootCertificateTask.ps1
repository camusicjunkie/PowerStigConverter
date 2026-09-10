function New-AnsibleRootCertificateTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName
    )

    begin {
        $taskGroups = @{}
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ TaskId = $baseId; StigName = $StigName }

            $location = Get-AnsibleOrganizationValue -Rule $rule -RuleType 'RootCertificate' -StigName $StigName

            $parsedCertificateName = if ($rule.Id -match '\.[a-z]$') {
                $rule.CertificateName -replace '\s\d$'
            }
            else {
                $rule.CertificateName
            }
            $parsedLocation = Split-Path -Path $location -Leaf

            $task = [ordered] @{
                'name' = 'Gather info for {0}' -f $rule.CertificateName
                'community.windows.win_certificate_info' = [ordered] @{
                    'store_name' = $parsedLocation
                    'thumbprint' = $rule.Thumbprint
                }
                'register' = 'server_2022_stig_{0}_certificate_info' -f ($rule.CertificateName -replace '\s')
            },
            [ordered] @{
                'name' = 'Assert {0} is set to {1}' -f $rule.CertificateName, $location
                'ansible.builtin.assert' = [ordered] @{
                    'that' = "$('server_2022_stig_{0}_certificate_info.certificates.issued_by' -f ($rule.CertificateName -replace '\s')) exists"
                    'fail_msg' = '{0} does not exist in the {1} certificate store' -f $rule.CertificateName, $parsedLocation
                }
            }

            Write-Verbose "  Task: $($task.name)"

            if (-not $taskGroups.ContainsKey($baseId)) {
                $taskGroups[$baseId] = @{
                    $rule.Id = $baseId
                    $rule.OrganizationValueRequired = $false

                    Rule = $rule
                    Name = $parsedCertificateName
                    NodeValue = $node.Location
                    Task = @{
                        'name' = '{0} | {1} | Assert {2} exists in the appropriate certificate store' -f $baseId, $rule.Severity.ToUpper(), $parsedCertificateName
                        'block' = @()
                        'when' = New-AnsibleVariable @navParams -TaskName $parsedCertificateName -Type Conditional
                    }
                }

                Write-Verbose "  TaskGroup: $($taskGroups[$baseId].Task.name)"

                $taskGroups[$baseId].Task.block += $task
            }
            else {
                $taskGroups[$baseId].Task.block += $task
            }

        }
    }
    end {
        $taskGroups.Values
    }
}
