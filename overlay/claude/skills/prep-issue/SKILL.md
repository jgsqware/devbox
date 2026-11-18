---
name: prep-issue
description: Prepare a Jira issue before and after coding it. (1) Pick - review the team's tickets on a topic through twg, cross-check them against the local repos (branches, open MRs, recent commits, code on the default branch) and recommend which one to take. (2) Brief - publish a "rack room" explainer artifact for the chosen ticket with tabs Why / Current / Target / How / Done when. (3) Review - after the implementation, update that same artifact with a Code review tab that explains the changes from most to least critical. Use on "/prep-issue", "quel ticket je pourrais prendre", "prépare le ticket PLT-123", "fais-moi une fiche du ticket", "ajoute la code review à la fiche", or when the user wants to understand a ticket before starting it.
---

# Prep issue

Three phases. Do the one the user asks for; each one can run in a separate session. Reply to the user in French, following their CLAUDE.md answer style. All page copy is in French.

## 0. Tools and ground rules

- **Jira / Confluence**: load the `twg` skill (and `twg-jira` for JQL). Run with `TWG_AGENT_DEFAULTS=1`. Save JSON outputs in the scratchpad and read them with `jq`: `workitem query` returns `.data.issues[]`, while `workitem get` returns `.data[0]` with an ADF description. Flatten it with `[.description | .. | objects | select(.type=="text") | .text] | join(" ")`.
- **Code**: look for local clones first (`find ~ -maxdepth 4 -name .git -not -path '*/.cache/*'`). Run `git fetch --all --prune` (read-only), then read the **remote default branch** (`git show origin/<default>:<path>`, `git grep … origin/<default>`), not the local checkout, which may be behind or on another branch. For repos that aren't cloned, use `glab` / `gh` or `twg search-code`.
- **Facts only**: every claim on the page comes from a ticket, a file or a command you ran. Label estimates as estimates. When a ticket's context disagrees with the code, say so on the page and in the reply.
- **No writes outside the page**: don't assign tickets, comment in Jira, create branches or push unless the user asks.
- **Memory**: at the end of phases 2 and 3, save or update a mind note (`capture`, `kind: doc`, `origin: <project>:<ticket-key-lowercase>-prep`) that holds the artifact URL. Phase 3 finds the page through that note. Give the `#ref` in the reply.

## 1. Pick: which ticket to take

1. **Find the tickets**: `twg rovo search "<topic>" --limit 10` to spot the team's project keys, then `twg jira workitem query --jql 'text ~ "<topic>" ORDER BY updated DESC' --fields summary,status,assignee,updated,project,priority --limit 60`. Say how many results you read and whether more pages exist.
2. **Shortlist** the open and unassigned ones, then `twg jira workitem get` each (one shell call, loop). Note the parent epic, links, prerequisites and "Done when" criteria.
3. **Check who is already on it** in each relevant repo:
   - branches named after the keys: `git branch -r | grep -iE '<KEY-1>|<KEY-2>'`;
   - recent activity: `git for-each-ref --sort=-committerdate refs/remotes --format='%(committerdate:short) %(refname:short) %(authorname)' | head -25`;
   - open MRs/PRs: `glab mr list` / `gh pr list`;
   - recent commits on the default branch that carry the keys.
4. **Check the starting point in the code**: does the flag, module or resource the ticket needs already exist? Which files would change?
5. **Recommend** one ticket with its reasons: unblocked, scope in one repo, what it unblocks, deadline, nobody on it, matches the user's recent work. Then give 2–3 alternatives in a table, and the tickets to avoid with the reason (who owns that stream, blockers, too many repos). Mention anything that would trip the user up (their local branch is behind, etc.). Stop there; the user picks.

## 2. Brief: the ticket explainer page

Load the `rack-room` skill and apply it exactly (start from its `tokens.css`), plus the artifact tooling (quickstart / artifact-design). Write `<scratchpad>/<ticket-key-lowercase>.html` and publish it. `<title>`: `Fiche <KEY>`.

**Hero**: ticket key, parent epic, a plain one-sentence goal, status / assignee / priority pills, chips for repo, layer and accounts or environments, and 3–4 key figures (deadline, scope, a limit or quota, the tickets it unblocks).

**Tabs** routed on `#hash`, one view per tab:

1. **`#pourquoi` (Why)**: the rule, standard or user need behind the ticket; the concrete problem (a real hostname, account or flow); why the obvious alternative doesn't work; why the scope is what it is. Use a matrix when the rule is a grid of allowed and denied cases.
2. **`#actuel` (Current)**: an SVG bus diagram of today's state, with an animated packet on the problem path (`--bad`). Add a layer-by-layer table (layer / today / does it solve the problem, as pills) and the relevant current config or rules read from the default branch, with `file:line`. Add a callout for every gap between the ticket text and the code.
3. **`#cible` (Target)**: the same diagram after the change, with the blocked path crossed out and the compliant path in `--ok`. Show the concrete resulting config computed from the real manifests (new rows highlighted), and a "what changes / what doesn't change" list.
4. **`#comment` (How)**: numbered steps (`ol.pipe`, lit one by one, with a replay button) from the ticket's design. List the files to touch as `✎` path lines, and give copyable commands to start (fetch, branch from `origin/<default>`, the greps to run). Add a code sketch labelled as a sketch, with the names you couldn't verify.
5. **`#termine` (Done when)**: the ticket's acceptance criteria as a checklist, the risks to watch, and the ticket chain (what it depends on, what it unblocks, what runs in parallel).

**Footer**: the sources (ticket keys read, repo and commit) and what is an estimate.

**Reply**: the link, one line per tab, the surprises found while preparing (outdated ticket context, ordering traps), what is unverified, and that the page is private until shared.

## 3. Review: Code review tab, after the implementation

Run it once the branch is implemented (the user says it's done, or asks for the review on the page).

1. **Find the page**: search mind for the `<project>:<key>-prep` note and take its artifact URL. If the HTML file from phase 2 is no longer on disk, `Artifact action:"read"` the URL and build on the version it returns.
2. **Collect the change**: `git fetch`, then `git diff --stat origin/<default>...HEAD` and the full diff, plus `git log origin/<default>..HEAD`. Read the open MR if there is one. Read the CI or `terraform plan` / test output only if the user gives it or you ran it.
3. **Rank every change from most to least critical**:
   - **Critique**: can cut traffic, lose data or state, widen access, or touch production or shared resources. Also changes that move Terraform state (moved/import/removed blocks, renamed keys).
   - **Important**: behaviour changes on opt-in paths, validation and schema, default values, IAM or network rules for a new scope.
   - **Mineur**: docs, generated docs, formatting, tests, CI config with no effect on deploys.
4. **Add a tab `#review` "Code review"** after `#termine`. Order it as follows:
   - a header with branch, commits, files and lines changed, and an MR link if there is one;
   - one card per change, most critical first. Each card has a severity pill (`bad` = critique, `todo` = important, `ok` = mineur), the `file:line` paths, what changed in plain words, why, the risk, and how it was or must be checked. Use a short diff excerpt as a `.cmd` block only when it helps;
   - a "Checks" section with what passed, what failed with its output, and what was not run. Never claim a check you didn't run;
   - a "Before merge" list: open questions and the actions left for the user.
   Also mark the matching steps and criteria in `#comment` / `#termine` as done or not done.
5. **Publish** to the same file path, or with `url` from another session. Keep the title and icon. Update the mind note. Reply with the link, the top critical items in one line each, and what is still unchecked.
