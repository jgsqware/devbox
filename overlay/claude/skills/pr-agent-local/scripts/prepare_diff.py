#!/usr/bin/env python3
"""Prepare a local branch diff the PR-Agent way (The-PR-Agent/pr-agent, MIT).

- Asymmetric + dynamic context: 3+5 lines before each hunk, extended up to
  3+10 lines to reach the enclosing function/class; 3+1 lines after.
- PR-Agent hunk format: '__new hunk__' with new-file line numbers, then
  '__old hunk__' with removed lines (only when something was removed).
- Token-aware packing: if the diff exceeds the budget, drop deletion-only
  hunks, sort files by the repo's main languages then by size, pack until
  the budget, list the rest as "other modified files", then deleted files.
- Optional chunking (for improve) and injection of per-file summaries
  produced by describe ("AI-generated changes summary").

Stdlib only. Tokens are estimated as characters / 4.
Writes diff.md (or chunk-N.md) in --out and prints a JSON summary.
"""
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from collections import Counter

CTX = 3                # git's default context
EXTRA_BEFORE = 5       # patch_extra_lines_before
EXTRA_AFTER = 1        # patch_extra_lines_after
DYNAMIC_BEFORE = 10    # max_extra_lines_before_dynamic_context
NO_EXTEND = (".md", ".txt", ".rst")  # patch_extension_skip_types
SOFT_BUFFER = 1500     # OUTPUT_BUFFER_TOKENS_SOFT_THRESHOLD

IGNORE = [
    "*.lock", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "go.sum",
    "Cargo.lock", "poetry.lock", "uv.lock", "Gemfile.lock", "composer.lock",
    "*.min.js", "*.min.css", "*.map", "*.snap", "*.pb.go", "*_pb2.py",
    "*generated*", "dist/*", "build/*", "vendor/*", "node_modules/*",
    "*.png", "*.jpg", "*.jpeg", "*.gif", "*.ico", "*.svg", "*.webp", "*.pdf",
    "*.zip", "*.gz", "*.tar", "*.jar", "*.so", "*.dylib", "*.exe", "*.woff*",
    "*.ttf", "*.otf", "*.mp4", "*.mp3",
]

LANG = {
    "py": "Python", "js": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript",
    "ts": "TypeScript", "tsx": "TypeScript", "go": "Go", "rs": "Rust",
    "java": "Java", "kt": "Kotlin", "scala": "Scala", "rb": "Ruby", "php": "PHP",
    "c": "C", "h": "C", "cc": "C++", "cpp": "C++", "hpp": "C++", "cs": "C#",
    "swift": "Swift", "sh": "Shell", "bash": "Shell", "zsh": "Shell",
    "tf": "Terraform", "hcl": "Terraform", "yaml": "YAML", "yml": "YAML",
    "json": "JSON", "toml": "TOML", "sql": "SQL", "lua": "Lua", "nix": "Nix",
    "md": "Markdown", "html": "HTML", "css": "CSS", "scss": "CSS",
}

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$")


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed: {r.stderr.decode(errors='replace')}")
    return r.stdout.decode("utf-8", errors="replace")


def tokens(text):
    return len(text) // 4 + 1


def lang_of(path):
    base = os.path.basename(path)
    if base in ("Dockerfile", "Makefile"):
        return base
    ext = base.rsplit(".", 1)[-1].lower() if "." in base else ""
    return LANG.get(ext, ext or "Other")


def ignored(path):
    return any(fnmatch.fnmatch(path, p) or fnmatch.fnmatch(os.path.basename(path), p)
               for p in IGNORE)


def parse_diff(raw):
    """Split a -U0 diff into files with their hunks."""
    files, cur = [], None
    for line in raw.split("\n"):
        if line.startswith("diff --git "):
            cur = {"old": None, "new": None, "hunks": [], "binary": False}
            files.append(cur)
        elif cur is None:
            continue
        elif line.startswith("--- "):
            cur["old"] = None if line[4:] == "/dev/null" else line[6:]
        elif line.startswith("+++ "):
            cur["new"] = None if line[4:] == "/dev/null" else line[6:]
        elif line.startswith("Binary files"):
            cur["binary"] = True
        elif (m := HUNK.match(line)):
            os_, oc, ns, nc, hdr = m.groups()
            cur["hunks"].append({
                "ns": int(ns), "nc": 1 if nc is None else int(nc),
                "header": hdr.strip(), "add": [], "rem": [],
            })
        elif cur["hunks"] and line.startswith("+"):
            cur["hunks"][-1]["add"].append(line[1:])
        elif cur["hunks"] and line.startswith("-"):
            cur["hunks"][-1]["rem"].append(line[1:])
    return files


def new_content(path, head):
    if head is None:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                return f.read().split("\n")
        except OSError:
            return []
    return git("show", f"{head}:{path}", check=False).split("\n")


def window(h, lines, extend):
    """New-file window [lo, hi] (1-based) for a hunk, with dynamic context."""
    lo = h["ns"] if h["nc"] > 0 else h["ns"] + 1
    hi = h["ns"] + h["nc"] - 1 if h["nc"] > 0 else h["ns"]
    before = CTX + (EXTRA_BEFORE if extend else 0)
    after = CTX + (EXTRA_AFTER if extend else 0)
    start = max(1, lo - before)
    if extend and h["header"]:
        target = h["header"][:60]
        for k in range(lo - 1, max(0, lo - 1 - CTX - DYNAMIC_BEFORE), -1):
            if k <= len(lines) and lines[k - 1].strip().startswith(target):
                start = min(start, k)
                break
    return start, min(len(lines), hi + after)


def render_file(path, hunks, lines, drop_deletion_only, summary=None):
    extend = not path.endswith(NO_EXTEND)
    groups = []
    for h in hunks:
        lo, hi = window(h, lines, extend)
        if groups and lo <= groups[-1]["hi"] + 1:
            groups[-1]["hi"] = max(groups[-1]["hi"], hi)
            groups[-1]["hunks"].append(h)
        else:
            groups.append({"lo": lo, "hi": hi, "hunks": [h]})

    out = [f"## File: '{path}'"]
    if summary:
        out += ["", "### AI-generated changes summary:"]
        out += [s if s.startswith(("*", "-")) else f"* {s}" for s in summary.strip().split("\n")]
    shown = 0
    for g in groups:
        seq, n = [], g["lo"]
        pending = sorted(g["hunks"], key=lambda h: h["ns"])
        while n <= g["hi"] or pending:
            h = pending[0] if pending else None
            if h and h["nc"] > 0 and h["ns"] == n:
                seq += [("-", t, None) for t in h["rem"]]
                seq += [("+", t, h["ns"] + i) for i, t in enumerate(h["add"])]
                n += h["nc"]
                pending.pop(0)
            elif h and h["nc"] == 0 and h["ns"] + 1 == n:
                seq += [("-", t, None) for t in h["rem"]]
                pending.pop(0)
            elif n <= g["hi"]:
                seq.append((" ", lines[n - 1] if n <= len(lines) else "", n))
                n += 1
            else:  # deletion right after the window (or an out-of-order hunk)
                seq += [("-", t, None) for t in h["rem"]]
                seq += [("+", t, h["ns"] + i) for i, t in enumerate(h["add"])]
                pending.pop(0)
        has_add = any(s == "+" for s, _, _ in seq)
        has_rem = any(s == "-" for s, _, _ in seq)
        if drop_deletion_only and not has_add:
            continue
        shown += 1
        out += ["", f"@@ ... @@ {g['hunks'][0]['header']}".rstrip(), "__new hunk__"]
        out += [f"{no} {s}{t}" for s, t, no in seq if s != "-"]
        if has_rem:
            out.append("__old hunk__")
            out += [f"{s}{t}" for s, t, _ in seq if s != "+"]
    return ("\n".join(out) + "\n") if shown else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="target branch (merge-base is computed)")
    ap.add_argument("--wip", action="store_true", help="compare with the working tree")
    ap.add_argument("--budget", type=int, default=32000, help="token budget per prompt")
    ap.add_argument("--chunks", type=int, default=1, help="max chunks (improve: 3)")
    ap.add_argument("--summaries", help="JSON file {file: summary} from describe; '-' reads stdin")
    ap.add_argument("--summaries-json", help="same, inline JSON string")
    ap.add_argument("--out", help="output dir (default: <git-dir>/pr-agent/run)")
    a = ap.parse_args()

    base = git("merge-base", "HEAD", a.base).strip()
    head = None if a.wip else "HEAD"
    rng = [base] + ([] if a.wip else ["HEAD"])
    summaries = {}
    if a.summaries_json:
        summaries = json.loads(a.summaries_json)
    elif a.summaries == "-":
        summaries = json.load(sys.stdin)
    elif a.summaries:
        with open(a.summaries) as f:
            summaries = json.load(f)
    if not a.out:
        a.out = os.path.join(git("rev-parse", "--absolute-git-dir").strip(), "pr-agent", "run")

    files = parse_diff(git("diff", "-U0", "-M", "--no-color", "--no-ext-diff", *rng))
    deleted, skipped, cand = [], [], []
    for f in files:
        if f["new"] is None:
            deleted.append(f["old"])
            continue
        path = f["new"]
        if f["binary"] or ignored(path):
            skipped.append(path)
            continue
        if not f["hunks"]:
            continue  # pure rename
        cand.append({"path": path, "old": f["old"], "hunks": f["hunks"],
                     "lines": new_content(path, head)})

    # repo language priority (PR-Agent: sort by the repo's main languages)
    repo_langs = Counter(lang_of(p) for p in git("ls-files").split("\n") if p)
    full = {c["path"]: render_file(c["path"], c["hunks"], c["lines"], False,
                                   summaries.get(c["path"])) for c in cand}
    total = sum(tokens(t) for t in full.values())
    limit = a.budget - SOFT_BUFFER

    if total <= limit:
        mode, patches = "full", full
    else:
        mode = "compressed"
        patches = {c["path"]: render_file(c["path"], c["hunks"], c["lines"], True,
                                          summaries.get(c["path"])) for c in cand}
        patches = {p: t for p, t in patches.items() if t}
        deleted_only = [c["path"] for c in cand if c["path"] not in patches]
        deleted += [f"{p} (deletion-only hunks)" for p in deleted_only]

    order = sorted(patches, key=lambda p: (-repo_langs[lang_of(p)], lang_of(p), -tokens(patches[p])))

    chunks = [[] for _ in range(max(1, a.chunks))]
    used = [0] * len(chunks)
    other = []
    for p in order:
        t = tokens(patches[p])
        for i in range(len(chunks)):
            if used[i] + t <= limit:
                chunks[i].append(p)
                used[i] += t
                break
        else:
            other.append(p)
    chunks = [c for c in chunks if c]

    os.makedirs(a.out, exist_ok=True)
    written = []
    for i, c in enumerate(chunks, 1):
        body = "\n".join(patches[p] for p in c)
        if i == len(chunks) and other:
            body += "\nOther modified files (not shown, token budget):\n" + "\n".join(f"- {p}" for p in other) + "\n"
        if i == len(chunks) and deleted:
            body += "\nDeleted files:\n" + "\n".join(f"- {p}" for p in deleted) + "\n"
        name = "diff.md" if len(chunks) == 1 else f"chunk-{i}.md"
        with open(os.path.join(a.out, name), "w") as f:
            f.write(body)
        written.append({"file": os.path.join(a.out, name), "files": c, "tokens": used[i - 1]})
    if not chunks and (deleted or skipped):
        with open(os.path.join(a.out, "diff.md"), "w") as f:
            f.write("Deleted files:\n" + "\n".join(f"- {p}" for p in deleted) + "\n")

    json.dump({
        "base": base, "head": head or "working tree", "mode": mode,
        "estimated_tokens_full": total, "budget": a.budget,
        "outputs": written, "other_modified_files": other,
        "deleted_files": deleted, "skipped_files": skipped,
        "renamed": {c["path"]: c["old"] for c in cand if c["old"] and c["old"] != c["path"]},
    }, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
