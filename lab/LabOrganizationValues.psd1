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
}
