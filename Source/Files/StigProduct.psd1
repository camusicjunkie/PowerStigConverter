# Every STIG product the converter knows, keyed by the first part of the STIG name (the product),
# with what its STIG profile needs that the name does not spell out. A product missing here fails
# the conversion, and a test fails when downloaded STIG data has one, so a new product is a
# decision rather than a guess. See docs/adr/0029.
#
# OsFamily: the family the role asserts and dispatch skips rule types by (docs/adr/0010).
# Target: the kind of host every STIG of the product describes. WindowsServer's comes from its
#   variant instead (DC or MS).
@{
    'Adobe'            = @{ OsFamily = 'Windows' }
    'DotNetFramework'  = @{ OsFamily = 'Windows' }
    'FireFox'          = @{ OsFamily = 'Windows' }
    'Google'           = @{ OsFamily = 'Windows' }
    'IISServer'        = @{ OsFamily = 'Windows' }
    'IISSite'          = @{ OsFamily = 'Windows' }
    'InternetExplorer' = @{ OsFamily = 'Windows' }
    'MS'               = @{ OsFamily = 'Windows' }
    'Office'           = @{ OsFamily = 'Windows' }
    'OracleLinux'      = @{ OsFamily = 'RedHat' }
    'RHEL'             = @{ OsFamily = 'RedHat' }
    'SqlServer'        = @{ OsFamily = 'Windows' }
    'WindowsClient'    = @{ OsFamily = 'Windows'; Target = 'Client' }
    'WindowsDefender'  = @{ OsFamily = 'Windows' }
    'WindowsDnsServer' = @{ OsFamily = 'Windows' }
    'WindowsFirewall'  = @{ OsFamily = 'Windows' }
    'WindowsServer'    = @{ OsFamily = 'Windows' }
}
