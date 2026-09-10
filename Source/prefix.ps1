Register-ArgumentCompleter -CommandName New-AnsiblePlaybook -ParameterName StigName -ScriptBlock {
    param( $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters )

    $stigFiles = (Get-PowerStigFile -Type Name).BaseName
    $stigFiles | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

$script:organizationData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\OrganizationData.psd1
$script:accountPolicyData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\AccountPolicyData.psd1
$script:securityOptionData = Import-PowerShellDataFile -Path $PSScriptRoot\Files\SecurityOptionData.psd1
