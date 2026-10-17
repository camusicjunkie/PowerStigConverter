function Get-AnsibleRoleName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StigName
    )

    # 'All' is a STIG's scope, not a release of it, so the role is not named for it either.
    # See docs/adr/0019.
    ($StigName -replace '-All$').ToLower() -replace '[^\w]+', '_'
}
