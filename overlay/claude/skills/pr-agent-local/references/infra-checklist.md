# Infra checklist — house rules for deployment code

Applies when the branch touches Ansible (playbooks, task files, templates,
vars), deploy / backup / restore / migration scripts, or CI jobs. Built from
the review comments that human reviewers had to write on MRs that had passed
this skill (devops/dockers !276 and !277): every item below was a real
comment. The goal is that a human reviewer finds **nothing** left from this
list.

Confirm each `issue` with a minimal reproduction when the claim is about
tool behaviour (a 10-line playbook beats reading the engine source): one
"medium" finding of a fresh-reader pass was false (`until` + `failed_when`).

Walk **every** item, against the full files (open the included task files,
templates and vars: not only the diff). For each one, answer `ok`,
`issue` (with the trigger scenario) or `n/a`. Do not stop at 3: the key-issue
cap of `review` does not apply to this list.

## 1. Dry run parity

- `--check` (or `--dry-run`) runs without failing on: first install (nothing
  exists yet: folders, containers, volumes), the normal upgrade, a re-run with
  the same version, and each failure input. A `chdir` to a folder created by an
  earlier task fails in check mode before the skip.
- **The dry run predicts what the real run will do.** For each decision the
  real run takes (backup or not, recreate or not, delete or not), list its
  inputs and ask: does check mode see the same input? Typical gaps: a pull that
  does not happen (no image ID, and a local tag can be an **old build** of a
  tag the vendor published again), a command that is skipped (empty `rc` /
  `stdout`), a file not written yet. Either fetch the real input read-only
  (registry HEAD, `*_info` module, `check_mode: false` on a read-only command)
  or say in the output that the prediction is unverified. A dry run that
  states the opposite of what will happen is a bug, even if the real run is
  safe.
- Read-only probes run in check mode (`check_mode: false`); destructive steps
  are gated (`when: not ansible_check_mode`) and reported instead.
- When the prediction needs an outside source (registry, API), every answer
  is handled: found, **not found** (the real run would stop: so must the dry
  run), unreachable (say "not verified"), and platform-specific cases (an
  index digest that changed for another architecture; architecture names
  that differ between `ansible_architecture` and Docker).

## 2. Decisions use data and booleans, not display text

- A `when:` / `failed_when:` / `until:` must read a boolean or a structured
  value, **never a string built for the operator** (`summary is match('healthy')`).
  Keep one fact as the gate, and derive the display text from it.
- Lists and dicts built with a Jinja loop (`{% for %}…{{ out }}`) come back as
  a **string** in recent ansible-core: indexing them gives characters. Build
  them as YAML lists of expressions.
- The state that decides "is this a first install / is there data" is the
  **data** (volume, database, file), not a container or process state: a
  stopped container still has data.

## 3. Destructive steps

- Before deleting or overwriting (volume rm, `find -delete`, `DROP`, restore
  over existing data), check that **everything needed to rebuild is present**
  (backup files exist and are not empty), and stop before the first destructive
  step otherwise.
- Destructive sequences are in a `block` with a `rescue` that tells the
  operator the exact state and the command to recover (for example the
  pre-operation backup folder).
- A retention or cleanup step can delete the artefact the current run is
  using (the backup being restored, the newest good backup). Check what it
  protects.
- A step that can fail half-way leaves no half-done artefact that later steps
  will take as valid: write a completion marker last, or remove on failure.
- Re-running the playbook (retry after a failure, same version again) does
  not replace the good artefact with a bad one (a backup taken after the
  migration becoming the default rollback target), and the messages of the
  re-run still point to the right artefact (the first pre-operation backup,
  not the one the retry just took; and not one from an older history).

## 4. Inputs and injection

- Every value from a prompt, `-e`, a file on the host or a manifest that goes
  into a path, a `shell:` / `command:` or a template is validated (regex,
  membership in a known list) and passed through `| quote` in commands.
  `../`, spaces and `$(…)` are the test cases.
- Values read back from a file the playbook wrote earlier (manifest, state
  file) are inputs too.

## 5. Images and versions

- No unpinned image (`busybox`, `:latest`): pin a tag or a digest.
- A tag is mutable: when the exact build matters (rollback, restore), record
  and use the **digest**.

## 6. Secrets

- Templates and tasks that render secrets have `diff: false` (and `no_log`
  where the output holds them). `--diff` must not print passwords.
- Credentials are not on a command line (use the container's environment,
  `MYSQL_PWD`, files with 0600).

## 7. Health checks really check

- A health check proves the service works end to end (database reachable,
  keys loaded), not only that a web server answers. Verify what the endpoint
  actually tests (it may answer OK with the database down).
- Commands that always exit 0 (some CLI health checks) are parsed.
- Messages distinguish "nothing is running" from "running and broken".

## 8. Messages and docs match the code

- Every claim in the MR description, the commit messages, comments and docs
  (what the output says, what was tested, what is skipped) matches the code
  and the observed output. Quote the code or the output when checking.
- Error messages name the next action (command, folder, doc section).

## 9. CI and tests

- New or changed playbooks are covered by a CI lint job for their path
  (yamllint, `--syntax-check`, `ansible-lint`), like the existing jobs in
  `.gitlab-ci.yml`.
- The description lists the scenarios that were run, **including the failure
  paths** (failed health check, missing input, interrupted step), and the
  dry-run cases from §1.

## 10. Traceability

- The MR title or description carries the Jira key (or says there is none).
