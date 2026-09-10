function New-AnsibleRootCertificateTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [string] $Path
    )

    begin {
        $items = [System.Collections.ArrayList]::new()
    }
    process {
        foreach ($rule in $InputObject) {
            # skip this rule if it is a duplicate of another rule
            if (-not [string]::IsNullOrEmpty($rule.DuplicateOf)) { continue }

            $baseId = $rule.Id -replace '\.[a-z]$'
            $navParams = @{ TaskId = $baseId; StigName = $StigName }

            $location = Get-AnsibleOrganizationValue -Rule $rule -RuleType 'RootCertificate' -StigName $StigName -Path $Path

            # The org settings file leaves Location blank for the site to fill in, and
            # Get-AnsibleOrganizationValue returns nothing when it is still empty. There is no
            # certificate store to check without it, so skip the rule; Test-PowerStigOrgValue
            # has already warned which id needs filling in.
            if ([string]::IsNullOrEmpty($location)) { continue }

            $parsedCertificateName = if ($rule.Id -match '\.[a-z]$') {
                $rule.CertificateName -replace '\s\d$'
            }
            else {
                $rule.CertificateName
            }
            $parsedLocation = Split-Path -Path $location -Leaf
            $registerName = 'server_2022_stig_{0}_certificate_info' -f ($rule.CertificateName -replace '\s')

            $tasks = [ordered] @{
                'name' = 'Gather info for {0}' -f $rule.CertificateName
                'community.windows.win_certificate_info' = [ordered] @{
                    'store_name' = $parsedLocation
                    'thumbprint' = $rule.Thumbprint
                }
                'register' = $registerName
            },
            [ordered] @{
                'name' = 'Assert {0} is set to {1}' -f $rule.CertificateName, $location
                'ansible.builtin.assert' = [ordered] @{
                    'that' = "$registerName.certificates.issued_by exists"
                    'fail_msg' = '{0} does not exist in the {1} certificate store' -f $rule.CertificateName, $parsedLocation
                }
            }

            $groupTask = @{
                'name' = '{0} | {1} | Assert {2} exists in the appropriate certificate store' -f $baseId, $rule.Severity.ToUpper(), $parsedCertificateName
                'block' = [System.Collections.ArrayList]::new()
                'when' = New-AnsibleVariable @navParams -TaskName $parsedCertificateName -Type Conditional
            }

            foreach ($task in $tasks) {
                Write-Verbose "  Task: $($task.name)"

                $item = @{
                    GroupId = $baseId
                    Task = $task
                    Output = @{
                        Rule = $rule
                        Name = $parsedCertificateName
                        Task = $groupTask
                    }
                }

                $null = $items.Add($item)
            }
        }
    }
    end {
        Group-AnsibleTask -InputObject $items.ToArray()
    }
}
