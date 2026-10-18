# AAP job templates and the `never` tag

Research pass for #178 (map #176): does `tags: [long_running, never]` behave in AAP the way it does
in `ansible-playbook --tags`? Facts from primary docs only; inferences are marked. Checked 2026-10-18
against the Ansible docs "latest" and Red Hat AAP 2.5 "Using automation execution".

Sources:
- Ansible Tags: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html
- Ansible reuse (import vs include table): https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse.html
- AAP 2.5 Job templates: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_automation_execution/controller-job-templates
- AAP 2.5 Schedules: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_automation_execution/controller-schedules

## Answer

Yes, by documentation. AAP's Job Tags and Skip Tags fields defer to the Ansible Tags page ("For more
information and examples see Tags in the Ansible documentation"), so `never` semantics are
ansible-core's. AAP documents no tag behaviour of its own. Two job templates on one playbook (default
= no tags; long-running = Job Tags `long_running`) are expressible. The one gap is whether a
schedule can carry its own tag values (below).

## Findings

1. **`never`.** "If you assign the `never` tag to a task or play, Ansible skips that task or play
   unless you specifically request it (`--tags never`) or another tag defined for that task."
   The docs' own example is `tags: [ never, debug ]`, "only runs when you specifically request the
   `debug` or `never` tags." So `[long_running, never]` runs under Job Tags `long_running` and is
   skipped by a template with empty Job Tags. (Ansible Tags)
2. **Default selection.** `--tags all` is "run all tasks, tagged and untagged except if `never`
   (default behavior)". So a template with no Job Tags skips `never` tasks. (Ansible Tags)
3. **Skip wins.** "Skipping always takes precedence over explicit tags." (Ansible Tags)
4. **AAP fields.** Job Tags: "specify which parts of the playbook should be executed". Skip Tags:
   "specify certain tasks or parts of the playbook to skip". Both link to the Ansible Tags page, and
   both support **Prompt on launch**. (AAP Job templates)
5. **`always`.** "Ansible will always run that task or play, unless you specifically skip it
   (`--skip-tags always`) or another tag defined on that task." Fact gathering is tagged `always`
   and "can be skipped if you apply a tag to the play and you skip it directly (`--skip-tags`) or
   indirectly when you use `--tags` and omit it." Role argument-spec validation is also `always`.
   `--tags untagged` is overridden by `always`; `--tags tagged` is overridden by `never`.
   (Ansible Tags)
6. **import_tasks vs include_tasks.** "With plays, blocks, the `role` keyword, and static imports,
   Ansible applies tag inheritance, adding the tags you define to every task inside the play, block,
   role, or imported file." "Tag inheritance does *not* apply to dynamic reuse with `include_role`
   and `include_tasks`"; use `apply: tags:` or a block to get it. The reuse page's table: imports
   show all tags under `--list-tags`, includes do not; options "apply to all child tasks in import"
   but "only to include task itself" for includes. (Ansible Tags; Ansible reuse)
7. **Schedules.** A schedule is created from the main Schedules page (resource type "Job template")
   or from a template's Schedules tab. Wizard steps documented: Create schedule, Define rules,
   Schedule exceptions. The Schedules chapter does not mention tags or prompts. The Job templates
   chapter says: "If you want to be able to specify `extra_vars` on a schedule, you must select
   **Prompt on launch** for Variables on the job template, or enable a survey on the job template."
   (AAP Schedules; AAP Job templates)

## Consequences for this repo (inference, not stated by the docs)

- `main_task.yml` uses `import_tasks` with `tags: cat1|cat2|cat3`. Per (6) those tags are added to
  every task in the file. A task tagged `[long_running, never]` inside `cat3.yml` therefore carries
  `[long_running, never, cat3]`. Per (1), "another tag defined for that task" being requested lifts
  `never`, so a run with Job Tags `cat3` would also run it. Only `long_running` or `never` alone, or
  a skip of `cat3`/`long_running`, keeps it out. If long-running tasks must not run under a plain
  category tag, `never` alone is not sufficient while the import tags propagate. Worth a lab check
  before relying on it.
- The `always` tasks in `main_task.yml` (OS assert, server-core fact, env fact) run under any Job
  Tags, and are lost only by Skip Tags `always`. The default `when:` on each import is applied to
  every imported task (6), so `*_catN: false` still skips them.
- Separate schedules per template are supported: schedules are created per job template. Whether a
  template may have several schedules, and whether a schedule may override Job Tags/Skip Tags, is
  not stated in the pages read. Two templates with fixed Job Tags/Skip Tags each avoid needing it.

## Not established

- Whether a schedule can override Job Tags/Skip Tags (only the `extra_vars` rule is documented).
- Explicit statements on multiple templates sharing one playbook (nothing prohibits it; nothing
  documents it).
- How AAP versions older than 2.5 differ; only 2.5 and current ansible docs were read.
