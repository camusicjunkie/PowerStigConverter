@{
    # A role variable is one no organization value feeds - the site fills it in. Two scopes:
    #
    #   PerRule  one variable per rule, <prefix>_<id>_<name>, because the value differs rule by
    #            rule. Each entry names the task the generator builds the reference from.
    #   PerRole  one variable for the whole role, <prefix>_<name>, because every rule of the type
    #            reads the same one. Declared as an empty list for the site to fill in - both
    #            uses so far are lists of IIS objects the generated tasks loop over.
    IisLogging               = @{ PerRule = @('LogPath') }
    WebConfigurationProperty = @{ PerRule = @('website') }
    MimeType                 = @{ PerRule = @('website') }
}
