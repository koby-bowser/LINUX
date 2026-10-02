---
name: feedback-ansible-gotchas
description: "Ansible-core 2.19 behavioral gotchas hit repeatedly while building playbooks in this repo — check these first when something silently doesn't run"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 05f38780-fe5a-4cbf-a339-2806ded87760
  modified: 2026-09-03T15:11:09.630Z
---

Recurring, non-obvious ansible-core behaviors discovered the hard way in this repo. Worth
checking against these BEFORE assuming a new bug when a playbook silently does nothing or fails
oddly:

- **`group_vars/`/`host_vars/` must live under the inventory's directory or the playbook's own
  directory** — not the project root, even if that "feels" like the natural place. In this repo
  they live at `playbooks/group_vars/all/` (siblings of the playbooks, not the project root),
  because playbooks live in `playbooks/`. Wrong placement fails silently with `'x' is undefined`,
  no hint that it's a path problem.
- **`include_tasks` + `loop` + `tags` on the include statement does NOT reliably propagate tags to
  the tasks inside the included file.** Symptom: `--tags X` shows `included: ... (item=...)` but
  then runs literally nothing from inside the file, no error, no "skipping" line either. Fix: tag
  each task INSIDE the included file explicitly instead of relying on inheritance.
- **Untagged `pre_tasks` are silently excluded entirely (not even shown as "skipping") when
  `--tags X` is passed** — unlike a runtime `when:`-based skip, which does print a line. Any
  pre_task that must always run regardless of which `--tags` subset is requested needs
  `tags: [always]` explicitly.
- **`ansible.builtin.command` expands a leading `~` in its string-form arguments using the
  CONTROLLER user's home directory** (e.g. `koby`), even when the actual command runs over SSH
  against a different remote user (e.g. `admin` on another host). It silently produces a wrong
  path like `/home/koby/foo` instead of letting the remote shell expand `~` to `/home/admin`. Fix:
  never use `~` in a `command:` string that's itself an `ssh`/`scp` invocation — hardcode or
  compute the real absolute remote path instead.
- **A `block:` supports `become`/`when`/`delegate_to`/`tags` but NOT `loop`.** To loop over a
  multi-task sequence with a shared `delegate_to`, wrap the tasks in a separate `tasks/*.yml` file
  and `include_tasks` + `loop` it — but note `include_tasks` itself doesn't reliably accept
  `become`/`delegate_to` either in this ansible-core version (`'become' is not a valid attribute
  for a TaskInclude`) — put `become`/`delegate_to` on a `block:` INSIDE the included file instead.
- **Complex nested dict/list Jinja literals containing chained `.split(x)[i]` inside a single
  `set_fact` can fail** with a confusing `object of type 'list' has no attribute 1` error. Fix:
  split into two `set_fact` steps — one to compute the intermediate list, a second simpler one to
  build the final structure referencing it by name.

See [[project-dns-cert-automation]] for the playbook these were found in.
