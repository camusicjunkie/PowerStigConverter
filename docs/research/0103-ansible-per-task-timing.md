# Per-task timing in Ansible and AAP

Research for #177 (map #176). Question: what can the lab capture per-task durations with, without
extra setup where possible? Checked 2026-10-18 against the lab's ansible-core 2.21.5 (WSL) and
upstream `devel`/`main`. Primary sources only: Ansible docs, the Ansible/AWX/ansible.posix source.

**Result.** The lab can capture per-task timing today with no setup: `log_path` is already on and
its lines carry millisecond timestamps, including one at every `TASK [...]` line. The three named
callbacks (`profile_tasks`, `timer`, `json`) are all in the `ansible.posix` collection, which the
lab does not have installed; `ansible-core` 2.21.5 ships none of them. AAP job events carry a
timestamp per event, so durations can be derived there, but no event carries a ready-made duration.

## Summary

| Mechanism | Where it lives | Per-task duration? | Lab (WSL) today |
|---|---|---|---|
| `log_path` timestamps | ansible-core | Derived: diff consecutive `TASK` line timestamps | **Yes, already on** |
| `ansible.posix.profile_tasks` | `ansible.posix` collection | Yes, printed per task plus a sorted recap | Needs `ansible-galaxy collection install ansible.posix` and one `callbacks_enabled` line |
| `ansible.posix.json` | `ansible.posix` collection | Yes, `task.duration.start`/`end` | Same install; replaces the stdout callback |
| `ansible.posix.timer` | `ansible.posix` collection | No, whole-play total only | Same install; not useful here |
| AAP job events | Controller API | Derived from event `created` timestamps | Not applicable to the lab; relevant to production |

## 1. `log_path` (ansible-core)

- `log_path` / `ANSIBLE_LOG_PATH`: "File to which Ansible will log on the controller. When not set
  the logging is disabled." Source: ansible-core
  [`config/base.yml`](https://github.com/ansible/ansible/blob/devel/lib/ansible/config/base.yml)
  (`DEFAULT_LOG_PATH`).
- Line format is a Python `logging` format string,
  `%(asctime)s p=%(process)d u=%(user)s n=%(name)s %(levelname)s| %(message)s`. Source:
  [`utils/display.py`](https://github.com/ansible/ansible/blob/devel/lib/ansible/utils/display.py).
  `asctime` is local time with milliseconds.
- Observed in the lab's own log (`lab/Invoke-StigLabRun.ps1` writes `log_path = ansible.log`):

  ```
  2026-10-18 01:13:43,357 p=73954 u=camus n=ansible INFO| PLAY [all] ****
  2026-10-18 01:13:43,366 p=73954 u=camus n=ansible INFO| TASK [Gathering Facts] ****
  ```

- A task's duration is the gap between its `TASK [...]` line and the next one (or the
  `PLAY RECAP`). That is the whole-task time as the strategy sees it, not per host.
- Caveat: nothing is logged between task start and finish, so a task's end is only implied by the
  next task's start. Time spent between tasks (handlers, fact gathering, `include`s) is attributed
  to the preceding task.

## 2. `ansible.posix.profile_tasks`

- Collection: `ansible.posix` (not in ansible-core). Doc: "adds additional console output next to
  the configured stdout callback"; shows "task start timestamp," "length of previous task," and
  "current elapsed playbook execution time," plus a summary of the most/least time-consuming
  tasks. Source:
  [profile_tasks docs](https://docs.ansible.com/ansible/latest/collections/ansible/posix/profile_tasks_callback.html).
- Enable: `[defaults] callbacks_enabled = ansible.posix.profile_tasks` (same page; the
  `callbacks_enabled` key itself is in `config/base.yml`, `CALLBACKS_ENABLED`, added 2.11).
- Options (same page): `datetime_format` (env `PROFILE_TASKS_DATETIME_FORMAT`, ansible.posix
  3.0.0), `output_limit` (default `20`, env `PROFILE_TASKS_TASK_OUTPUT_LIMIT`), `sort_order`
  (`descending` default, `ascending`, `none`; env `PROFILE_TASKS_SORT_ORDER`), `summary_only`
  (default false; env `PROFILE_TASKS_SUMMARY_ONLY`; 1.5.0).
- Output: a line after each task header, `<timestamp> (<elapsed of previous task>)  <total
  elapsed>`, and a `TASKS RECAP` block of task name and seconds. Source:
  [`callback/profile_tasks.py`](https://github.com/ansible-collections/ansible.posix/blob/main/plugins/callback/profile_tasks.py)
  (`tasktime()`, `v2_playbook_on_stats()`).
- It keys on task UUID, so it is per task, not per host; with several hosts or the `free`
  strategy it does not give per-host durations (same source). The lab has one host.
- `output_limit` defaults to 20, so the recap truncates unless raised. The role has far more than
  20 tasks, so set `PROFILE_TASKS_TASK_OUTPUT_LIMIT` high.

## 3. `ansible.posix.timer`

- Collection: `ansible.posix`. Doc: aggregate callback that "adds total play duration to the play
  stats." Source:
  [timer docs](https://docs.ansible.com/ansible/latest/collections/ansible/posix/timer_callback.html).
- Gives one number for the whole run. It does not give per-task timing, so it does not answer
  #177 beyond a sanity check on totals.

## 4. JSON callback

- Collection: `ansible.posix` (`ansible.posix.json`); a stdout callback, so it replaces the
  default screen output ("Set as stdout in config"). Options `json_indent` (default 4) and
  `show_custom_stats`. Source:
  [json docs](https://docs.ansible.com/ansible/latest/collections/ansible/posix/json_callback.html).
- Timing: the source records `duration: {start: ...}` when a task or play starts and sets
  `duration.end` when a result arrives, both as UTC ISO-8601 with a `Z` suffix. Source:
  [`callback/json.py`](https://github.com/ansible-collections/ansible.posix/blob/main/plugins/callback/json.py)
  (`_new_task()`, `_record_task_result()`). It stores start and end, not a pre-computed
  duration; subtract them.
- With `free`/`host_pinned`/custom strategies a task can appear more than once, once per host
  result, with matching task IDs (json docs).
- The sibling `ansible.posix.jsonl` is the streaming variant (one JSON object per line, does not
  keep results in memory). Its docs do not mention timing fields; not verified.
- Cost for the lab: the JSON callback owns stdout, so the human-readable output the lab shows
  and the `failures.csv` parsing in `Invoke-StigLabRun.ps1` (which reads `TASK [` lines from
  `ansible.log`) would need rethinking. `ansible.log` is separate from stdout, so the log
  still carries the usual text if `log_path` stays set, but confirm before relying on it.

## 5. AAP job events

- A job event is created per callback hook (`playbook_on_task_start`, `runner_on_ok`, and so on);
  `runner_on_*` events are created for each `playbook_on_task_start`. Source: AWX
  [`docs/job_events.md`](https://github.com/ansible/awx/blob/devel/docs/job_events.md).
- Event types include `runner_on_start` ("Host Started") and `playbook_on_task_start` ("Task
  Started"). Each event row has `created` and `modified` timestamps. Source: AWX
  [`models/events.py`](https://github.com/ansible/awx/blob/devel/awx/main/models/events.py)
  (`BasePlaybookEvent`).
- Read them from `/api/v2/jobs/<job_id>/job_events/` (Red Hat, [Jobs in automation
  controller](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.4/html/automation_controller_user_guide/controller-jobs)).
- There is no per-task duration field in the events. A duration is derived: per host,
  `runner_on_start.created` to the matching `runner_on_ok`/`failed`/`skipped` `created`; or the
  gap between consecutive `playbook_on_task_start` events. `created` is when the event was
  recorded on the controller, so it includes event-pipeline latency. (That last point is my
  inference from the model, not a documented statement.)
- The job itself has `started`, `finished` and `elapsed` for the whole run only (Red Hat jobs
  docs above).
- Not documented in these sources: whether the controller's own `profile_tasks`-style callback
  runs in a job. Enabling `callbacks_enabled` inside an execution environment is a separate
  question and is not answered here.

## Recommendation for the lab (input to #179)

1. Zero setup: derive durations from `ansible.log` `TASK [...]` timestamps. It already exists for
   every run, including runs that lose the host part way.
2. For a direct, sorted measurement without parsing, install `ansible.posix` in the WSL
   collection path alongside `ansible.windows` and `community.windows` and enable
   `ansible.posix.profile_tasks` with `PROFILE_TASKS_TASK_OUTPUT_LIMIT` raised. It is additive to
   stdout and does not disturb the current log parsing.
3. Use `ansible.posix.json` only if per-task machine-readable start/end is needed; it takes over
   stdout.
4. Skip `timer`.
5. Rule-level (V-id, block) timing needs the task names, which carry the V-id; all of the above
   report by task name, so grouping by block is a post-processing step.

## Not verified

- Behaviour of `ansible.posix` callbacks under ansible-core 2.21.5 was read from docs and source,
  not run; the lab does not have the collection.
- The exact `created` semantics of AAP events beyond the model fields above.
