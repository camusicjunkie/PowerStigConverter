# Per rule type: the ansible_os_family its adapter's module targets - 'Windows' for every
# adapter built against win_dsc or a Windows-native module, 'RedHat' for the two built against
# native Ansible modules for RHEL/OracleLinux (see docs/adr/0008, docs/adr/0009).
#
# ConvertTo-AnsiblePlaybook reads this to skip a rule whose adapter exists but does not target
# the conversion's own OsFamily, rather than build it anyway - see docs/adr/0010. A rule type
# missing from this table is not restricted to any OsFamily; GeneratorCoverage.Tests.ps1 is what
# keeps every adapter listed, not a runtime check.
@{
    'AccountPolicy' = 'Windows'
    'AuditPolicy' = 'Windows'
    'AuditSetting' = 'Windows'
    'IisLogging' = 'Windows'
    'MimeType' = 'Windows'
    'Permission' = 'Windows'
    'Registry' = 'Windows'
    'RootCertificate' = 'Windows'
    'SecurityOption' = 'Windows'
    'Service' = 'Windows'
    'SqlDatabase' = 'Windows'
    'SqlLogin' = 'Windows'
    'SqlProtocol' = 'Windows'
    'SqlScriptQuery' = 'Windows'
    'SqlServerConfiguration' = 'Windows'
    'SslSettings' = 'Windows'
    'UserRight' = 'Windows'
    'WebAppPool' = 'Windows'
    'WebConfigurationProperty' = 'Windows'
    'WindowsFeature' = 'Windows'
    'NxFileLine' = 'RedHat'
    'NxService' = 'RedHat'
}
