# Accounts and groups that exist only on a domain controller. A Permission entry naming one cannot
# resolve on a member server or a client, so the generator leaves it out. See docs/adr/0020.
@{
    Principal = @(
        'Server Operators'
        'Account Operators'
    )
}
