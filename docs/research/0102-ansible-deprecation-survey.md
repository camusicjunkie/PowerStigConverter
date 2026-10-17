# Ansible deprecation survey of generated output

Research pass: is anything the generators emit (beyond `community.windows.win_audit_policy_system` and
`community.windows.win_certificate_info`) deprecated, tombstoned, redirected, or scheduled for removal?
No code under `Source/` or `tests/` was changed. Checked 2026-10-17 against the lab's installed
ansible-core 2.21.5, ansible.windows 3.8.0 and community.windows 3.3.0 (WSL `~/.ansible/collections`,
pipx ansible-core), plus upstream `main`.

**Result: no. Only the two known modules are flagged.** One more deprecation (`INJECT_FACTS_AS_VARS`)
appeared in older lab logs and is already fixed in the templates.

## 1. What is emitted, and its status

Collection `runtime.yml` = `meta/runtime.yml` in the installed collection (CW = community.windows,
AW = ansible.windows). "Changelog" = `CHANGELOG.rst` in the same collection.

| Feature | Emitted at | Collection | Status | Source |
|---|---|---|---|---|
| `win_audit_policy_system` | Task/Build-AnsibleAuditPolicyTask.ps1:13 | community.windows 3.3.0 | **redirected, removal 4.0.0** (known) | CW runtime.yml `plugin_routing` entry |
| `win_certificate_info` | Task/Build-AnsibleRootCertificateTask.ps1:29 | community.windows 3.3.0 | **redirected, removal 4.0.0** (known) | CW runtime.yml |
| `win_security_policy` | Task/Build-AnsibleAccountPolicyTask.ps1:17, SecurityOptionTask.ps1:15 | community.windows 3.3.0 | ok - absent from CW runtime.yml routing and from the 3.0.0 deprecation list | CW runtime.yml; CW CHANGELOG 3.0.0 "Deprecated Features"; upstream `main` runtime.yml |
| `win_dsc` (params `resource_name`, `module_version`, resource props) | AuditSetting:23, IisLogging:44, MimeType:13, SqlDatabase:24, SqlLogin:29, SqlProtocol:31, SqlScriptQuery:50, SqlServerConfiguration:32, SslSettings:46, WebAppPool:41, WebConfigurationProperty:15 | ansible.windows 3.8.0 | ok | AW runtime.yml (only 3 domain tombstones); `win_dsc.py` DOCUMENTATION has no deprecated options |
| `win_user_right` (`name`, `users`, `action`) | UserRight:51, :68 | ansible.windows | ok | AW runtime.yml; module docs |
| `win_powershell` (`script`) | UserRight:41 | ansible.windows | ok | same |
| `win_acl` (`path,user,rights,type,inherit,propagation`) | Permission:37 | ansible.windows | ok | same |
| `win_regedit` (`path,name,data,type,state`) | Registry:53 | ansible.windows | ok. Forward-slash `path` was removed in 2.0.0; generator emits backslashes (Registry:27-33). `key`/`entry`/`datatype` aliases are not used | AW CHANGELOG 2.0.0 "Removed Features"; `win_regedit.py` aliases |
| `win_feature` (`name,state`, `register`) | WindowsFeature:13 | ansible.windows | ok. Removed return value `restart_needed` (3.0.0) is not read; generator reads `.msg` and `failed` only | AW CHANGELOG 3.0.0 |
| `win_service_info` (`name`) | Service:30 | ansible.windows | ok | AW runtime.yml |
| `win_reboot` | Roles/main_handler.yml:3 | ansible.windows | ok, no options passed (`*_sec` aliases unused) | AW runtime.yml |
| `win_ping` | lab/Invoke-StigLabRun.ps1:123 | ansible.windows | ok | AW runtime.yml |
| `assert`, `set_fact`, `import_tasks`, `copy`, `lineinfile`, `systemd_service` | Get-AnsibleVariableName:57, Resolve-AnsibleOrganizationValue:151, Roles/main_task*.yml, Roles/main_handler*.yml, Task/NxFileLine:28,43, NxService:28, SslSettings:33 | ansible.builtin (core 2.21.5) | ok. `systemd_service` is the current name (the old `systemd` is the alias) | `ansible-doc`/core plugin routing, no deprecation block |
| Task keywords `when, loop, register, block, notify, changed_when, failed_when, check_mode, become, tags` | various Task/*.ps1 | core | ok. `changed_when: true/false` and `when` strings evaluate to real booleans, which ansible-core 2.19+ conditional rules require | ansible-core 2.19/2.20 porting guides |
| Filters/tests `product, unique, list, map, zip, dict, lower, length, default, search, is <state>` | Roles/main_task.yml:22, Task/SqlLogin, SslSettings, Service | core | ok | core filter docs |
| Role `meta/main.yml` `collections:` and `galaxy_info.min_ansible_version: "2.15"` | Roles/main_meta.yml | core | ok, but see 3 | CW/AW `requires_ansible >=2.16.0` |
| Facts via `ansible_facts[...]` | Roles/main_task.yml:5-16 | core | ok - this is the `INJECT_FACTS_AS_VARS` remedy | commit 075f88d |
| Lab `ansible.cfg`: `inventory, roles_path, log_path, host_key_checking, callback_result_format` | lab/Invoke-StigLabRun.ps1:96-101 | core | ok - none appear in core's `deprecated:` settings list | `lib/ansible/config/base.yml` scan |
| Lab inventory `ansible_connection: winrm`, `ansible_winrm_*` | lab/Invoke-StigLabRun.ps1:73-83 | ansible.windows/core | ok | AW runtime.yml |

## 2. Needs action

Only the two known modules. Both are a one-word FQCN swap; the options are unchanged.

| Now | Replace with | Notes |
|---|---|---|
| `community.windows.win_audit_policy_system` | `ansible.windows.win_audit_policy_system` | Same module, moved. CW 3.0.0 changelog: "redirection will be removed in 4.0.0". Needs ansible.windows >= 3.x in the lab (3.8.0 installed ships it). |
| `community.windows.win_certificate_info` | `ansible.windows.win_certificate_info` | Same. |

Lab evidence: 132 + 32 deprecation lines for these two across `lab/.local/stig-ws2025/runs/*/ansible.log`,
66 + 16 in the WSL logs for the two latest runs. Nothing else flagged.

## 3. Upcoming, not yet flagged

- **community.windows 4.0.0**: removes the redirects above. CW runtime.yml has the comment "Tombstone these
  redirections when 4.0.0 is released". `win_security_policy` is **not** in the list; no upstream
  announcement found. If it ever moves it would follow the same pattern, so keep watching.
- **Role `collections: [community.windows]`** (Roles/main_meta.yml) stays needed while `win_security_policy`
  is emitted.
- **ansible-core 2.24**: `INJECT_FACTS_AS_VARS` default flips to `False`. Generated roles are safe because
  they read `ansible_facts[...]`. The same core `base.yml` scan lists settings removed in 2.22-2.23
  (`DEFAULT_JINJA2_NATIVE`, `DEFAULT_NULL_REPRESENTATION`, `DEFAULT_UNDEFINED_VAR_BEHAVIOR`,
  `STRING_TYPE_FILTERS`, `DEFAULT_MANAGED_STR`, ...); nothing emitted or written to `ansible.cfg` uses them.
  ansible.windows 3.x changelog also notes an internal `text` module_utils removal in 2.24 (collection
  concern, not ours). ansible-core 2.21 porting guide lists no playbook-facing deprecations.
- **`min_ansible_version: "2.15"`**: below both collections' `requires_ansible >=2.16.0`. Not deprecated
  by anything, but the role's declared floor is not one the collections support. Consider "2.16".

## 4. The `INJECT_FACTS_AS_VARS` warnings (39 hits)

All 39 are in the four 2026-10-08 runs (`061729`, `062053`, `062736`, `124724`). The roles generated then
referenced top-level facts in `tasks/main.yml`: `ansible_os_family`, `ansible_distribution`,
`ansible_distribution_major_version` (lines 5-10) and `ansible_os_installation_type` (line 16). Commit
`075f88d` "Read scaffolding facts through ansible_facts" removed them. The 2026-10-09 and 2026-10-17
runs have **0** hits. The remaining `ansible_version`/`ansible_os_family` text in `Source/` is Plaster
prompt wording and ADR prose, not emitted tasks.

Other log lines, none deprecation-related: "file ... is empty and had no tasks to include" (empty
`handlers/generated.yml`, `cat3.yml`), and one "Failed to cleanup running WinRM command".

## Sources

- Installed: `ansible_collections/community/windows/meta/runtime.yml`, `.../CHANGELOG.rst` (3.0.0 Deprecated Features);
  `ansible_collections/ansible/windows/meta/runtime.yml`, `.../CHANGELOG.rst` (2.0.0, 3.0.0); module `.py` DOCUMENTATION blocks;
  ansible-core 2.21.5 `lib/ansible/config/base.yml` (`deprecated:` keys).
- https://github.com/ansible-collections/community.windows/blob/main/meta/runtime.yml
- https://github.com/ansible-collections/ansible.windows/blob/main/meta/runtime.yml
- https://docs.ansible.com/projects/ansible/14/porting_guides/porting_guide_core_2.21.html
- https://docs.ansible.com/ansible/latest/porting_guides/porting_guide_core_2.20.html
