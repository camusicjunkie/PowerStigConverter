Register-ArgumentCompleter -CommandName New-AnsiblePlaybook -ParameterName StigName -ScriptBlock {
    param( $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters )

    $stigFiles = (Get-PowerStigFile -Type Name).BaseName
    $stigFiles | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

$script:organizationData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\OrganizationData.psd1
$script:ruleTypeOsFamily = Import-PowerShellDataFile -Path $PSScriptRoot\Files\RuleTypeOsFamily.psd1
$script:accountPolicyData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\AccountPolicyData.psd1
$script:securityOptionData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\SecurityOptionData.psd1
$script:ruleCorrection = Import-PowerShellDataFile -Path $PSScriptRoot\Files\RuleCorrection.psd1

# The fact a domain-only condition reads. See docs/adr/0025 and 0026.
$script:domainMemberCondition = "ansible_facts['windows_domain_member']"

# DISA's second domain-only wording for a user right: who must hold it on a domain member, and that
# no one may hold it off a domain. See docs/adr/0025.
$script:userRightDomainJoined = '^If the following accounts or groups are not defined for the ".+" user right on domain-joined systems, this is a finding[.:]$'
$script:userRightNondomainJoined = '^If any accounts or groups are defined for the ".+" user right on nondomain-joined systems, this is a finding\.$'
