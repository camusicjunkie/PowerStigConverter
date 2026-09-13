@{
    # A role variable is one no organization value feeds - the site fills it in. One variable per
    # rule, <prefix>_<id>_<name>, because the value differs rule by rule; each entry names the task
    # the generator builds the reference from.
    #
    # The role-scoped ones - the lists of IIS sites and app pools every rule of a type reads - are
    # not here: a generator declares those itself as a RoleVariable output key, so the reference
    # and the declaration cannot name different things and a Server STIG, which references no
    # website at all, declares none. See #57.
    IisLogging = @{ PerRule = @('LogPath') }
}
