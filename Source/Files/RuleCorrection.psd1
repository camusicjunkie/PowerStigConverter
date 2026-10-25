# Corrections to PowerStig's processed data, applied before conversion, keyed by processed file
# (name and revision) then rule id. See docs/adr/0020. A correction that finds nothing to change warns.
#
# RemoveEntry: drops the access control entries whose fields all match.
# Field: replaces a rule's child element while it still holds From.
# ReplaceInRawString: replaces From with To in the check text while From occurs there exactly once.
# OrganizationalSetting: replaces an org setting attribute while it still holds From.
# HardCodedRule: moves a rule from type From to type To while it is still a From, setting its
#   Field values (DscResource is the attribute) and adding its OrganizationalSetting where the
#   org settings have no entry. PowerStig's own .log does the same as HardCodedRule(...).
@{
    'WindowsClient-10-3.5' = @{
        'V-220969' = @{
            Reason = "DISA's check text names 'Enterprise Admin Group' and 'Domain Admin Group', which no Identity entry prefixes, so the domain-only split (ADR 0025) cannot place them."
            ReplaceInRawString = @(
                @{ From = 'Enterprise Admin Group'; To = 'Enterprise Admins Group' }
                @{ From = 'Domain Admin Group'; To = 'Domain Admins Group' }
            )
        }
    }
    'WindowsClient-10-3.6' = @{
        'V-220969' = @{
            Reason = "DISA's check text names 'Enterprise Admin Group' and 'Domain Admin Group', which no Identity entry prefixes, so the domain-only split (ADR 0025) cannot place them."
            ReplaceInRawString = @(
                @{ From = 'Enterprise Admin Group'; To = 'Enterprise Admins Group' }
                @{ From = 'Domain Admin Group'; To = 'Domain Admins Group' }
            )
        }
    }
    'WindowsClient-11-2.6' = @{
        'V-253430.b' = @{
            Reason = "PowerStig gives V-253430 two sub-rules for the same US DOD CCEB Interoperability Root CA 2 (9B74...); .a already checks it."
            Field = @{
                DuplicateOf = @{ From = ''; To = 'V-253430.a' }
            }
        }
        'V-253492' = @{
            Reason = "DISA's check text names 'Enterprise Admin Group' and 'Domain Admin Group', which no Identity entry prefixes, so the domain-only split (ADR 0025) cannot place them."
            ReplaceInRawString = @(
                @{ From = 'Enterprise Admin Group'; To = 'Enterprise Admins Group' }
                @{ From = 'Domain Admin Group'; To = 'Domain Admins Group' }
            )
        }
    }
    'WindowsClient-11-2.7' = @{
        'V-253430.b' = @{
            Reason = "PowerStig gives V-253430 two sub-rules for the same US DOD CCEB Interoperability Root CA 2 (9B74...); .a already checks it."
            Field = @{
                DuplicateOf = @{ From = ''; To = 'V-253430.a' }
            }
        }
        'V-253492' = @{
            Reason = "DISA's check text names 'Enterprise Admin Group' and 'Domain Admin Group', which no Identity entry prefixes, so the domain-only split (ADR 0025) cannot place them."
            ReplaceInRawString = @(
                @{ From = 'Enterprise Admin Group'; To = 'Enterprise Admins Group' }
                @{ From = 'Domain Admin Group'; To = 'Domain Admins Group' }
            )
        }
    }
    'WindowsServer-2016-MS-2.10' = @{
        'V-225015' = @{
            Reason = "PowerStig left DISA's check text as the default: a regex alternation, 'Review the text file.' and the SIDs."
            OrganizationalSetting = @{
                Identity = @{
                    From = 'Enterprise Admins,Domain Admins,(Local account and member of Administrators group|Local account),Guests,Review the text file.,S-1-5-root domain-519,S-1-5-domain-512,S-1-5-114  or S-1-5-113,S-1-5-32-546'
                    To = 'Enterprise Admins,Domain Admins,Local account and member of Administrators group,Guests'
                }
            }
        }
        'V-225078' = @{
            Reason = "Create symbolic links was given V-225015's deny-network list, which would grant the right to Enterprise Admins, Domain Admins and Guests. The STIG grants it to Administrators."
            OrganizationalSetting = @{
                Identity = @{
                    From = 'Enterprise Admins,Domain Admins,(Local account and member of Administrators group|Local account),Guests'
                    To = 'Administrators'
                }
            }
        }
    }
    'WindowsServer-2022-DC-2.8' = @{
        'V-254392' = @{
            Reason = "PowerStig read '(RX)' in the check text as an account. It names no principal, and the rule's real entries were not parsed."
            RemoveEntry = @{ Principal = '(RX)' }
        }
    }
    'WindowsServer-2025-DC-1.1' = @{
        'V-278085' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254338 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'RegistryPolicyFile'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Netbt\Parameters'; ValueName = 'NoNameReleaseOnDemand'; ValueType = 'Dword'; ValueData = '1' }
            }
        }
        'V-278101' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254354 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'RegistryPolicyFile'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer'; ValueName = 'NoDriveTypeAutoRun'; ValueType = 'Dword'; ValueData = '255' }
            }
        }
        'V-278139' = @{
            Reason = "PowerStig read '(RX)' in the check text as an account. It names no principal, and the rule's real entries were not parsed."
            RemoveEntry = @{ Principal = '(RX)' }
        }
        'V-278212' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254462 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'Registry'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; ValueName = 'EnablePlainTextPassword'; ValueType = 'Dword'; ValueData = '0' }
            }
        }
    }
    'WindowsServer-2025-MS-1.1' = @{
        'V-278085' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254338 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'RegistryPolicyFile'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Netbt\Parameters'; ValueName = 'NoNameReleaseOnDemand'; ValueType = 'Dword'; ValueData = '1' }
            }
        }
        'V-278101' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254354 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'RegistryPolicyFile'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer'; ValueName = 'NoDriveTypeAutoRun'; ValueType = 'Dword'; ValueData = '255' }
            }
        }
        'V-278178' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254429 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'RegistryPolicyFile'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; ValueName = 'LocalAccountTokenFilterPolicy'; ValueType = 'Dword'; ValueData = '0' }
            }
        }
        'V-278180' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254431 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'RegistryPolicyFile'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Rpc'; ValueName = 'RestrictRemoteClients'; ValueType = 'Dword'; ValueData = '1' }
            }
        }
        'V-278181' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. As 2022's V-254432, '4 (or less)' is the organization's, defaulting to 4."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'Registry'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; ValueName = 'CachedLogonsCount'; ValueType = 'String'; ValueData = ''; OrganizationValueRequired = 'True'; OrganizationValueTestString = "'{0}' -le '4'" }
                OrganizationalSetting = @{ ValueData = '4' }
            }
        }
        'V-278212' = @{
            Reason = "PowerStig's 4.30.0 .log forces it to a ManualRule ('::*::.'), giving no reason. 2022's V-254462 is the same value."
            HardCodedRule = @{
                From = 'ManualRule'; To = 'RegistryRule'
                Field = @{ DscResource = 'Registry'; Ensure = 'Present'; Key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; ValueName = 'EnablePlainTextPassword'; ValueType = 'Dword'; ValueData = '0' }
            }
        }
        'V-278001.c' = @{
            Reason = "Server Operators exists only on a domain controller. PowerStig's 2022 .log removes the same entry from V-254254."
            RemoveEntry = @{ Principal = 'Server Operators' }
        }
        'V-278184' = @{
            Reason = 'PowerStig wrote the identities as prose, with sentence periods and padding no account carries.'
            OrganizationalSetting = @{
                Identity = @{
                    From = 'Enterprise Admins., Domain Admins.,Local account and member of Administrators group,Guests.'
                    To = 'Enterprise Admins,Domain Admins,Local account and member of Administrators group,Guests'
                }
            }
        }
    }
}
