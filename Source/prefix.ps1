# Passes the completer's arguments on: prefix.ps1 runs before the module's functions are defined,
# so the function itself cannot be handed over here
Register-ArgumentCompleter -CommandName New-AnsiblePlaybook -ParameterName StigName -ScriptBlock {
    Get-StigNameCompletion @args
}

$script:organizationData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\OrganizationData.psd1
$script:ruleTypeOsFamily = Import-PowerShellDataFile -Path $PSScriptRoot\Files\RuleTypeOsFamily.psd1
# Every STIG product the profile knows. See docs/adr/0029.
$script:stigProduct = Import-PowerShellDataFile -Path $PSScriptRoot\Files\StigProduct.psd1
$script:accountPolicyData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\AccountPolicyData.psd1
$script:securityOptionData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\SecurityOptionData.psd1
$script:ruleCorrection = Import-PowerShellDataFile -Path $PSScriptRoot\Files\RuleCorrection.psd1
# A DC's Kerberos policy task runs this as its script. See docs/adr/0028.
$script:defaultDomainPolicyScript = Get-Content -Path $PSScriptRoot\Files\Set-DefaultDomainPolicyValue.ps1 -Raw

# The fact a domain-only condition reads. See docs/adr/0025 and 0026.
$script:domainMemberCondition = "ansible_facts['windows_domain_member']"

# DISA's second domain-only wording for a user right: who must hold it on a domain member, and that
# no one may hold it off a domain. See docs/adr/0025.
$script:userRightDomainJoined = '^If the following accounts or groups are not defined for the ".+" user right on domain-joined systems, this is a finding[.:]$'
$script:userRightNondomainJoined = '^If any accounts or groups are defined for the ".+" user right on nondomain-joined systems, this is a finding\.$'
