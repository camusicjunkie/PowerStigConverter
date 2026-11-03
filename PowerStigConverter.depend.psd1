@{
    PSDependOptions  = @{
        AddToPath = $True
        Target    = 'build/modules'
        Tags      = 'Build'
    }

    ModuleBuilder    = 'latest'
    InvokeBuild      = 'latest'
    # 6.2.0 is the first release carrying the whole Should-* assertion family the suite uses;
    # 6.0.0 has no Should-Invoke, Should-MatchString or Should-BeHashtable.
    Pester           = '6.2.0'
    PSScriptAnalyzer = 'latest'

    # The module's own RequiredModules: the built module will not import without them
    'powershell-yaml' = 'latest'
    Plaster          = 'latest'
}
