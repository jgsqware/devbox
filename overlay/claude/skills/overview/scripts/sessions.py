#!/usr/bin/env python3
"""Claude Code sessions of THIS box: open now, or active in the last HOURS.

Usage: sessions.py [HOURS] [SELF_SESSION_ID]     (default 48 h)
Stdlib only: also runs on a remote box via `ssh host python3 - 48 < sessions.py`.
Prints one JSON array. Read-only: never writes anywhere.
"""
import glob, json, os, re, socket, subprocess, sys, time

HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 48
SELF = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("CLAUDE_CODE_SESSION_ID", "")
HOME = os.path.expanduser("~")
CUTOFF = time.time() - HOURS * 3600
KEY = re.compile(r"\b(?!(?:UTF|SHA|ISO|RFC|CVE|GHSA|TLS|HTTP|MD|AES|RSA|AVX|DNS|X|P)-)[A-Z][A-Z0-9]{1,9}-\d{1,6}\b")
MR = re.compile(r"(?:merge_requests/|(?<![\w/])!)(\d{2,5})\b")
HOST = socket.gethostname().split(".")[0]


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


# Open sessions: ~/.claude/sessions/<pid>.json whose process still runs.
live = {}
for f in glob.glob(f"{HOME}/.claude/sessions/*.json"):
    try:
        s = json.load(open(f))
    except Exception:
        continue
    if alive(s.get("pid", 0)):
        live[s.get("sessionId")] = s


def git_state(cwd):
    if not cwd or not os.path.isdir(cwd):
        return {"exists": False}
    def g(*a):
        r = subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else None
    try:
        br = g("rev-parse", "--abbrev-ref", "HEAD")
        if br is None:
            return {"exists": True, "git": False}
        dirty = len([l for l in (g("status", "--porcelain") or "").splitlines() if l])
        ab = g("rev-list", "--left-right", "--count", "@{u}...HEAD")
        behind, ahead = (ab.split() if ab else (None, None))
        return {"exists": True, "branch": br, "dirty": dirty,
                "ahead": int(ahead) if ahead else None,
                "upstream": ab is not None}
    except Exception:
        return {"exists": True, "git": "?"}


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


out = []
for f in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl"):
    sid = os.path.basename(f)[:-6]
    mtime = os.path.getmtime(f)
    if mtime < CUTOFF and sid not in live:
        continue
    if sid == SELF:
        continue
    title = last_prompt = last_text = branch = cwd = first_ts = last_ts = entry = ""
    first_prompt, n_user, keys, mrs = "", 0, set(), set()
    for line in open(f, errors="ignore"):
        try:
            e = json.loads(line)
        except Exception:
            continue
        t = e.get("type")
        ts = e.get("timestamp")
        if ts:
            first_ts = first_ts or ts
            last_ts = ts
        branch = e.get("gitBranch") or branch
        cwd = e.get("cwd") or cwd
        entry = e.get("entrypoint") or entry
        if t == "ai-title":
            title = e.get("aiTitle") or title
        elif t == "custom-title":
            title = e.get("customTitle") or title
        elif t == "last-prompt":
            last_prompt = e.get("lastPrompt") or last_prompt
        elif t == "user" and not e.get("isMeta") and not e.get("isSidechain"):
            c = (e.get("message") or {}).get("content")
            if isinstance(c, str) and c.strip() and not c.startswith("<"):
                n_user += 1
                first_prompt = first_prompt or c
                keys |= set(KEY.findall(c))
                mrs |= set(MR.findall(c))
        elif t == "assistant" and not e.get("isSidechain"):
            tx = text_of((e.get("message") or {}).get("content"))
            if tx.strip():
                last_text = tx
                keys |= set(KEY.findall(tx))
                mrs |= set(MR.findall(tx))
    if n_user == 0 or entry == "sdk-cli":   # empty or headless `claude -p` run
        continue
    s = live.get(sid, {})
    lt = last_text.strip()
    out.append({
        "host": HOST,
        "id": sid,
        "name": s.get("name", ""),
        "title": title,
        "cwd": (cwd or s.get("cwd", "")).replace(HOME, "~"),
        "open": sid in live,
        "status": s.get("status", "closed"),
        "first": first_ts[:16], "last": last_ts[:16],
        "turns": n_user,
        "branch": branch,
        "first_prompt": first_prompt[:200].replace("\n", " "),
        "last_prompt": last_prompt[:200].replace("\n", " "),
        "last_reply_tail": lt[-500:].replace("\n", " "),
        "ends_with_question": lt.rstrip("*_ `").endswith("?"),
        "keys": sorted(keys)[:8],
        "mrs": sorted(mrs, key=int)[:8],
        "git": git_state(cwd),
    })

out.sort(key=lambda x: x["last"], reverse=True)
print(json.dumps(out, ensure_ascii=False))
