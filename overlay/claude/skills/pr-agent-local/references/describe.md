# describe — PR description

Adapted from PR-Agent `pr_description_prompts.toml` (defaults: description on, semantic file types on, diagram on).

## Rules

- Focus on new code (`+` lines).
- Commit messages and branch name may be partial, simplistic or outdated: compare them with the diff and use them only as a reference.
- Title and summary put the **most significant changes** first.
- Code names and paths in backticks; bullets with `- `.

## Fields (PR-Agent `PRDescription` schema)

| Field | Content |
|---|---|
| `type` | One or more of: `Bug fix`, `Tests`, `Enhancement`, `Documentation`, `Other`. |
| `title` | Concise, descriptive, captures the main theme. Follow the repo's commit convention if `git log` shows one (e.g. `feat:` prefix, French messages). |
| `description` | 1-4 bullets, each up to 8 words, ordered by importance, one per group of changes. Sub-bullets for large changes. |
| `changes_diagram` | Mermaid `flowchart LR` of the main changes, short and readable. Declare nodes first as `id["description"]` (always double quotes), then links `a -- "text" --> b`. Leave it out if no diagram helps. |
| `pr_files` | Up to 20 files, every file analysed whatever its size: `filename`, `changes_title` (5-10 words), `label` (bug fix, tests, enhancement, documentation, error handling, configuration changes, dependencies, formatting, miscellaneous…), `changes_summary` (1-4 bullets). |

## Output format

Render as Markdown ready to paste into a GitHub / GitLab PR or MR:

```markdown
### **Title**
<title>

### **Type**
Enhancement, Bug fix

### **Description**
- ...
- ...

### Diagram
```mermaid
flowchart LR
  a["..."] -- "..." --> b["..."]
```

### File Walkthrough
<details><summary><b>Enhancement</b> (2 files)</summary>

| File | Changes |
|---|---|
| `src/foo.py` | **<changes_title>**<br>- bullet<br>- bullet |
</details>
```

Group the walkthrough by `label`, one collapsible block per label.
