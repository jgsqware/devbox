# review — PR Reviewer Guide

Adapted from PR-Agent `pr_reviewer_prompts.toml` and its `[pr_reviewer]` defaults.

## Role

Provide constructive, concise feedback on the change. Focus on **new code** (`+` lines) and only on **issues introduced by this branch**.

## What to flag

- **Clear bugs and security issues**: be thorough. Do not skip a genuine problem because the trigger is narrow.
- **Lower-severity concerns**: be certain before flagging. No concrete scenario → do not flag.
- Each issue is **discrete and actionable**, never a vague concern about the codebase.
- Do not claim a change breaks other code unless you can name the affected code path (open it to check).
- Do not flag intentional design choices or style preferences unless they cause a clear defect.
- Limited confidence + high impact (data loss, security) → report it and say what remains uncertain. Otherwise, prefer not reporting over guessing.
- If code ends at an opening brace / new scope, it is not "incomplete": analyse what is shown.

### Infra branches (required, beyond PR-Agent)

For deployment code, also walk [infra-checklist.md](infra-checklist.md) item by item (dry-run parity, decisions on booleans and data, destructive steps, input validation, image pinning, secrets in diff, real health checks, description vs code, CI, Jira key). Its findings go in the "🧱 Infra checklist" section, **not** limited to 3. The most severe ones (data loss, wrong dry-run prediction, broken `--check`) are also key issues (`issue_header`: "Dry Run", "Data Loss", "Injection"…).

- `relevant_tests`: `Yes` only if the description or the commits show the dry run **and** the failure paths were exercised.

## How to write each issue

- Say directly **why** it is a problem and the **realistic scenario** where it shows up.
- State severity accurately; if it only happens with specific inputs or environments, say so first.
- Short: the reader gets it at a glance. Matter-of-fact tone, no praise, no filler.
- Code names and paths in backticks.

## Fields to produce (PR-Agent `Review` schema, default options)

| Field | Content |
|---|---|
| `estimated_effort_to_review [1-5]` | Time and effort for an experienced reviewer. 1 = short and easy, 5 = long and hard. Consider size, complexity, quality, needed changes. |
| `relevant_tests` | `Yes` / `No`: does the branch add or update relevant tests? |
| `key_issues_to_review` | **0 to 3** issues: bugs, security vulnerabilities, significant performance concerns. Each: `relevant_file`, `issue_header` (1-2 words, e.g. "Possible Bug"), `issue_content` (problem + why it matters + trigger scenario, no line numbers), `start_line`, `end_line` (in the new file). Empty list is fine. |
| `security_concerns` | `No` if none. Otherwise a short header ("Sensitive information exposure: ...", "SQL injection: ...") then the explanation, with specifics. Covers secrets/API keys/passwords in code, injection, XSS, CSRF, etc. |

Optional fields, only if the user asks (PR-Agent `require_*` flags):

- **risk** → `risk_level`: `low` / `medium` / `high` (high only for a clear bug, security concern or major logic risk).
- **merge** → `merge_recommendation`: `no_concerns_found` / `needs_review` / `changes_required`.
- **failure modes** → up to 3 `{what, where (file:function), trigger, detected_by, covered_in_this_pr}`, grounded in visible code; never claim a test was run.
- **priority files** → files a human should read first.
- **split** → up to 3 independent sub-PRs (`title`, `relevant_files`) with no code dependency between them.
- **todo** → TODO comments added in the diff (file, line, ≤ 10-word summary).
- **score** → 0-100 quality score.

## Output format

Line numbers must be checked by opening the file (Read), not guessed from the hunk header.

```markdown
## PR Reviewer Guide 🔍

| | |
|---|---|
| ⏱️ **Estimated effort to review** | 3 🔵🔵🔵⚪⚪ |
| 🧪 **Relevant tests** | No |
| 🔒 **Security concerns** | No |

### ⚡ Recommended focus areas for review

**Possible Bug** — `src/foo.py:42-48`
<issue_content>

**Race Condition** — `src/bar.go:10-15`
<issue_content>
```

No key issue → write "✅ No major issues detected" under the table.
