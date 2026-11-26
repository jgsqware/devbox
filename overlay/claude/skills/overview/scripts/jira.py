#!/usr/bin/env python3
"""Jira items that wait on me, from every Jira THIS box reaches with `twg`
(today: gaming-1.atlassian.net from the gaming1 box). No twg → []. Read-only.
  - assigned to me and unresolved
  - reported by me, unresolved, and updated by someone else in the last 7 days
Flags `ball_in_my_court` when the last comment is not mine.
"""
import json, shutil, socket, subprocess

HOST = socket.gethostname().split(".")[0]
ME = "Julien Garcia Gonzalez"
out = []
if not shutil.which("twg"):
    print("[]")
    raise SystemExit


def q(jql, n=60):
    r = subprocess.run(
        ["twg", "--output", "json", "--output-summary", "none", "jira", "workitem", "query",
         "--jql", jql, "--fields",
         "summary,status,priority,duedate,updated,comment,customfield_10020,issuetype,assignee,reporter",
         "--limit", str(n)], capture_output=True, text=True, timeout=90)
    if r.returncode:
        raise RuntimeError((r.stderr or r.stdout).strip()[:200])
    return json.loads(r.stdout)["data"]["issues"]


try:
    seen = set()
    for role, jql in (
        ("assignee", "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"),
        ("reporter", "reporter = currentUser() AND assignee != currentUser() AND resolution = Unresolved "
                     "AND updated >= -7d ORDER BY updated DESC"),
    ):
        for i in q(jql):
            if i["key"] in seen:
                continue
            seen.add(i["key"])
            cs = (i.get("comment") or {}).get("comments") or []
            last = cs[-1] if cs else {}
            author = (last.get("author") or {}).get("displayName", "")
            sprints = i.get("customfield_10020") or []
            out.append({
                "box": HOST, "key": i["key"], "role": role, "url": i.get("url", ""),
                "type": (i.get("issuetype") or {}).get("name", ""),
                "summary": i["summary"], "status": i["status"]["name"],
                "status_cat": ((i["status"].get("statusCategory") or {}).get("key", "")),
                "priority": (i.get("priority") or {}).get("name", ""),
                "due": i.get("duedate") or "", "updated": i["updated"][:10],
                "sprint": next((s["name"] for s in sprints if s.get("state") == "active"), ""),
                "assignee": (i.get("assignee") or {}).get("displayName", ""),
                "last_comment_by": author, "last_comment_at": (last.get("created") or "")[:16],
                "last_comment": json.dumps(last.get("body", ""), ensure_ascii=False)[:300] if author and author != ME else "",
                "ball_in_my_court": bool(author) and author != ME,
            })
except Exception as e:
    out.append({"box": HOST, "error": f"twg: {e}"})
print(json.dumps(out, ensure_ascii=False))
