function Get-AnsibleApplicabilityCondition {
    <#
    .SYNOPSIS
        The condition a rule's check text puts on where it applies, or nothing when it applies
        everywhere.
    .DESCRIPTION
        A rule DISA marks NA off a domain runs only on a domain member. See docs/adr/0026.
    #>
    param ($Rule)

    # 'For domain controllers and standalone or nondomain-joined systems, this is NA' names a DC
    # too, but a member-server STIG is never applied to one.
    $offDomain = 'not a member of a domain, this is (NA|not applicable)|stand-?alone (or nondomain-joined )?systems,? this is (NA|not applicable)'
    if (([string] $Rule.RawString) -match $offDomain) {
        $script:domainMemberCondition
    }
}
