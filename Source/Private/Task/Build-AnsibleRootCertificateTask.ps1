function Build-AnsibleRootCertificateTask {
    <#
    .SYNOPSIS
        Gather a certificate by thumbprint and assert it is in the store the organization named.
    #>
    param ($Rule, $StigName, $StigId, $Resolution)

    $store = $Resolution.Value
    $baseId = Get-PowerStigBaseRuleId -Id $Rule.Id

    $parsedCertificateName = if (Test-PowerStigSubRuleId -Id $Rule.Id) {
        $Rule.CertificateName -replace '\s\d$'
    }
    else {
        $Rule.CertificateName
    }

    $registerName = Get-AnsibleRegisterName -TaskId $baseId -StigName $StigName -Suffix 'certificate_info'

    @{
        # Always a block: sub-rules of one requirement name several certificates.
        Group = $true
        GroupDetail = 'Assert {0} exists in the appropriate certificate store' -f $parsedCertificateName
        # Named outright, because these two read as a pair rather than as separate requirements.
        Task = @(
            @{
                Name = 'Gather info for {0}' -f $Rule.CertificateName
                Body = [ordered] @{
                    'community.windows.win_certificate_info' = [ordered] @{
                        'store_name' = $store.StoreName
                        'store_location' = $store.StoreLocation
                        'thumbprint' = $Rule.Thumbprint
                    }
                    'register' = $registerName
                }
            }
            @{
                Name = 'Assert {0} is set to {1}' -f $Rule.CertificateName, $store.StoreName
                Body = [ordered] @{
                    'ansible.builtin.assert' = [ordered] @{
                        'that' = "$registerName.certificates.issued_by exists"
                        'fail_msg' = '{0} does not exist in the {1} certificate store' -f $Rule.CertificateName, $store.StoreName
                    }
                }
            }
        )
    }
}
