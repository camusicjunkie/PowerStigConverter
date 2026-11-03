@{
    RootModule        = 'PowerStigConverter.psm1'

    # Replaced at build time with the version GitVersion derives
    ModuleVersion     = '0.0.0'

    GUID              = '14e8b90d-9646-4c5f-b74a-c899511a2ad6'
    Author            = 'John Steele'
    CompanyName       = 'BlueAndBlack'
    Copyright         = '(c) 2024 John Steele. Licensed under the MIT License.'
    Description       = "Converts the parsed STIG data in Microsoft's PowerStig module into Ansible roles."

    # Windows PowerShell 5.1, verified by running the suite on both engines rather than assumed.
    # Nothing in the module uses syntax above 5.1: ValidateScript's ErrorMessage was the one
    # 6.1+ construct, and it throws from inside the scriptblock instead.
    PowerShellVersion = '5.1'

    RequiredModules   = @('powershell-yaml', 'Plaster')

    # Always empty in source; Build-Module fills these in from Source/Public
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = 'STIG', 'PowerStig', 'Ansible', 'DISA', 'Compliance', 'Security', 'Windows'
            LicenseUri   = 'https://github.com/camusicjunkie/PowerStigConverter/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/camusicjunkie/PowerStigConverter'
            ReleaseNotes = 'https://github.com/camusicjunkie/PowerStigConverter/releases'
        }
    }
}
