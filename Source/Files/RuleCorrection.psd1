# Corrections to PowerStig's processed data, applied before conversion. Keyed by processed file
# (name and revision), then rule id. PowerStig fixes this kind of error with a .log beside each
# source STIG; these are the ones its data still carries. See docs/adr/0020.
#
# RemoveEntry drops the access control entries whose fields all match. OrganizationalSetting
# replaces an attribute of the org setting, only while it still holds From. A correction that
# finds nothing to change warns, so one the data has outgrown is noticed and removed.
@{
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
        'V-278139' = @{
            Reason = "PowerStig read '(RX)' in the check text as an account. It names no principal, and the rule's real entries were not parsed."
            RemoveEntry = @{ Principal = '(RX)' }
        }
    }
    'WindowsServer-2025-MS-1.1' = @{
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
