# PowerStigConverter

Converts Microsoft PowerStig's processed STIG XML into Ansible roles. The domain is the
translation between two vocabularies: DISA's STIG rules as PowerStig models them, and the
tasks, variables and toggles an Ansible role is made of.

## Language

### STIG data

**STIG rule**:
One hardening requirement from a DISA STIG, as PowerStig has processed it into XML. Carries an
id (`V-254343`), a severity, a rule type, and the properties that type needs.
_Avoid_: check, control, finding, setting

**Rule type**:
The family a STIG rule belongs to — `Registry`, `SecurityOption`, `UserRight`, `Service`,
`AccountPolicy`, `IisLogging`, `RootCertificate` and the rest. Determines which task generator
handles it and which organization value fields it needs.
_Avoid_: resource, category, DSC type

**Sub-rule**:
A STIG rule whose id carries a letter suffix (`V-254343.b`) because one requirement needs
several tasks. Sub-rules are collapsed into a single block task guarded by the base id.
_Avoid_: child rule, variant

**Duplicate rule**:
A STIG rule carrying a `DuplicateOf` pointing at another rule that already covers it. Produces
no task.
_Avoid_: alias, redundant rule

### Organization values

**Organization value**:
A value in a STIG rule that DISA deliberately leaves to the adopting organization — a minimum
password length, which identities hold a right, which certificate store to check. Rules
carrying one are flagged `OrganizationValueRequired`.
_Avoid_: org setting, site value, custom value. (Module identifiers use the American spelling
`Organization` throughout; British-spelled prose should still name the term this way.)

**Org settings file**:
The `*.org.default.xml` PowerStig ships beside each processed STIG, holding one
`OrganizationalSetting` per rule that needs an organization value. PowerStig ships the ones it
cannot answer blank.
_Avoid_: defaults file (that name belongs to the generated role's `defaults/`), org data

**Unanswered setting**:
An `OrganizationalSetting` that is present in the org settings file but whose value is empty —
a policy question nobody has answered yet. It is not a data error; it is the adopting
organization's decision, still outstanding.
_Avoid_: blank value, missing value, empty setting

**Missing setting**:
A rule that requires an organization value for which the org settings file carries no
`OrganizationalSetting` at all. Distinct from an unanswered setting: it usually means the org
settings file does not match the STIG version in hand.
_Avoid_: blank value, null setting

**Incomplete organization value**:
The collective for the two above — an organization value the org settings file does not answer,
whether because the setting is unanswered or because it is missing. It is the thing
`New-AnsiblePlaybook` refuses on, and it already names the public
`-AllowIncompleteOrganizationValue` switch and the `IncompleteOrganizationValue` error id. Name
the individual fault where the remedy matters, and this where it does not.
_Avoid_: gap

### Generated role

**Task generator**:
The adapter that turns STIG rules of one rule type into Ansible tasks — `Build-Ansible*Task`.
It supplies only what differs by type: the ansible module and the fields mapped into it.
`ConvertTo-AnsibleTask` owns everything every type does the same way. One adapter per supported
rule type; rule types without one produce nothing.
_Avoid_: converter, handler, builder

**Conditional toggle**:
The `prefix_<id>_when` variable in the role's `defaults/` that lets an operator switch a single
generated rule off. One per generated task group, derived from the tasks themselves so that
`defaults/` and `tasks/` cannot disagree.
_Avoid_: flag, switch, feature toggle

**Organization variable**:
The `prefix_<id>_<name>` variable in the role's `defaults/` holding an organization value, which
the generated task references rather than inlining. The single place an operator edits to answer
a policy question without regenerating the role. Not every variable in `defaults/` is one: the IIS
log path is shaped the same way but has no organization value behind it, so it is a role variable
the site fills in rather than one of these. See ADR-0004.
_Avoid_: default, parameter, override

**Variable prefix**:
The role-wide identifier stem derived from the STIG name (`server_2022_ms`), which every
generated variable name is built on.
_Avoid_: namespace, role prefix
