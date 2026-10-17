# Placeholder answers for the org settings PowerStig leaves blank, so a lab run exercises
# those rules instead of skipping them behind a failed assert. Keys are rule ids (wildcards
# allowed), values are the attribute to fill. These are for a disposable VM only.
@{
    # DoD Root CA certificates belong in the trusted root store.
    'V-278192.*' = @{ Location = 'Cert:\LocalMachine\Root' }
    # The interoperability cross-certificates belong in the untrusted store.
    'V-278193.*' = @{ Location = 'Cert:\LocalMachine\Disallowed' }
    'V-278194.*' = @{ Location = 'Cert:\LocalMachine\Disallowed' }
    # Renames a built-in account: the lab connects as 'ansible', so WinRM is unaffected.
    'V-278197' = @{ OptionValue = 'LabAdmin' }
    'V-278198' = @{ OptionValue = 'LabGuest' }
    # Server 2022 MS: the same questions under its own rule ids.
    'V-254442.*' = @{ Location = 'Cert:\LocalMachine\Root' }
    'V-254443' = @{ Location = 'Cert:\LocalMachine\Disallowed' }
    'V-254447' = @{ OptionValue = 'LabAdmin' }
    'V-254448' = @{ OptionValue = 'LabGuest' }
    # The antivirus and firewall services the STIG asks the organization to name: Defender's.
    'V-254248' = @{ ServiceName = 'WinDefend'; StartupType = 'Automatic' }
    'V-254265' = @{ ServiceName = 'mpssvc'; StartupType = 'Automatic' }
    # Edge's ProxySettings policy is a JSON string; a direct connection is the harmless answer.
    'V-235719' = @{ ValueData = '{"ProxyMode":"direct"}' }
    # Chrome's three blanks: an extension allowlist, and an encrypted search provider's name and URL.
    'V-221563' = @{ ValueData = 'oiigbmnaadbkfbmpbfijlflahbdbdgdf' }
    'V-221564' = @{ ValueData = 'Google Encrypted' }
    'V-221565' = @{ ValueData = 'https://www.google.com/search?q={searchTerms}' }
}
