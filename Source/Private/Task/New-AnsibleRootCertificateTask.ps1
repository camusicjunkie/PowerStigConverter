function New-AnsibleRootCertificateTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $StigName,

        [hashtable] $OrganizationalSetting = @{}
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

            # The certificate store is an organization value, so the task interpolates it rather
            # than naming a store. This rule used to be dropped outright when the value was
            # blank, which left a STIG requirement silently absent from the role; an unanswered
            # value now stops the conversion instead, or produces an assert. See docs/adr/0001.
            $resolution = Resolve-AnsibleOrganizationValue -Rule $rule -RuleType 'RootCertificate' -StigName $StigName -OrganizationalSetting $OrganizationalSetting
            # win_certificate_info takes the store and its location separately. Sending only the
            # store left the location to the module's LocalMachine default, which was right by
            # luck for every Cert:\LocalMachine\ store and wrong for anything under Cert:\CurrentUser\.
            $store = $resolution.Value

            $parsedCertificateName = if ($rule.Id -match '\.[a-z]$') {
                $rule.CertificateName -replace '\s\d$'
            }
            else {
                $rule.CertificateName
            }
            $registerName = '{0}_{1}_certificate_info' -f (Get-AnsibleVariablePrefix -StigName $StigName), ($baseId -replace 'V-' -replace '[^A-Za-z0-9]+', '_')

            $tasks = @(
                $resolution.Assert
                [ordered] @{
                    'name' = 'Gather info for {0}' -f $rule.CertificateName
                    'community.windows.win_certificate_info' = [ordered] @{
                        'store_name' = $store.StoreName
                        'store_location' = $store.StoreLocation
                        'thumbprint' = $rule.Thumbprint
                    }
                    'register' = $registerName
                }
                [ordered] @{
                    'name' = 'Assert {0} is set to {1}' -f $rule.CertificateName, $store.StoreName
                    'ansible.builtin.assert' = [ordered] @{
                        'that' = "$registerName.certificates.issued_by exists"
                        'fail_msg' = '{0} does not exist in the {1} certificate store' -f $rule.CertificateName, $store.StoreName
                    }
                }
            ).Where({ $null -ne $_ })

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
