#!/usr/bin/env python3
"""Open MRs / PRs that wait on me or that I wait on, from every forge THIS box
is logged in to (glab hosts + gh). Stdlib only; runs remotely through stdin.
Prints one JSON array; a forge that fails gives {"error": ...}. Read-only.
"""
import json, os, re, socket, subprocess

HOST = socket.gethostname().split(".")[0]
out = []


def run(cmd, timeout=40):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode:
        raise RuntimeError((r.stderr or r.stdout).strip()[:200])
    return json.loads(r.stdout)


def glab_hosts():
    f = os.path.expanduser("~/.config/glab-cli/config.yml")
    if not os.path.exists(f):
        return []
    hosts, in_hosts = [], False
    for line in open(f):
        if re.match(r"^hosts:\s*$", line):
            in_hosts = True
        elif in_hosts and re.match(r"^\S", line):
            in_hosts = False
        elif in_hosts and (m := re.match(r"^    ([A-Za-z0-9.-]+):\s*$", line)):
            hosts.append(m.group(1))
    return hosts


def gl(host, path):
    return run(["glab", "api", "--hostname", host, path])


for h in glab_hosts():
    try:
        me = gl(h, "user")["username"]
        mine = gl(h, "merge_requests?scope=created_by_me&state=opened&per_page=50")
        review = gl(h, f"merge_requests?scope=all&state=opened&reviewer_username={me}&per_page=50")
        assigned = gl(h, "merge_requests?scope=assigned_to_me&state=opened&per_page=50")
    except Exception as e:
        out.append({"box": HOST, "forge": h, "error": str(e)})
        continue
    seen = set()
    for role, lst in (("author", mine), ("reviewer", review), ("assignee", assigned)):
        for m in lst:
            if m["web_url"] in seen:
                continue
            seen.add(m["web_url"])
            pid, iid = m["project_id"], m["iid"]
            pipe, approved, unresolved = None, [], None
            try:
                d = gl(h, f"projects/{pid}/merge_requests/{iid}")
                pipe = (d.get("head_pipeline") or {}).get("status")
                a = gl(h, f"projects/{pid}/merge_requests/{iid}/approvals")
                approved = [x["user"]["username"] for x in a.get("approved_by", [])]
                disc = gl(h, f"projects/{pid}/merge_requests/{iid}/discussions?per_page=100")
                unresolved = sum(1 for x in disc for n in x["notes"][:1]
                                 if n.get("resolvable") and not n.get("resolved"))
            except Exception:
                pass
            out.append({
                "box": HOST, "forge": h, "role": "author" if m["author"]["username"] == me else role,
                "ref": f'{m["references"]["full"]}', "url": m["web_url"], "title": m["title"],
                "draft": m.get("draft", False), "status": m.get("detailed_merge_status"),
                "conflicts": m.get("has_conflicts"), "pipeline": pipe,
                "approved_by": approved, "i_approved": me in approved,
                "unresolved": unresolved,
                "reviewers": [r["username"] for r in m.get("reviewers", [])],
                "author": m["author"]["username"],
                "updated": m["updated_at"][:16], "created": m["created_at"][:10],
            })

# GitHub
Q = """query($q:String!){search(query:$q,type:ISSUE,first:30){nodes{... on PullRequest{
  url title isDraft updatedAt createdAt mergeable reviewDecision author{login}
  repository{nameWithOwner}
  reviewThreads(first:50){nodes{isResolved}}
  commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}}"""
try:
    me = run(["gh", "api", "user"])["login"]
    seen = set()
    for role, q in (("author", f"is:pr is:open author:{me}"),
                    ("reviewer", f"is:pr is:open review-requested:{me}")):
        r = run(["gh", "api", "graphql", "-f", f"query={Q}", "-f", f"q={q}"])
        for p in r["data"]["search"]["nodes"]:
            if not p or p["url"] in seen:
                continue
            seen.add(p["url"])
            roll = ((p["commits"]["nodes"] or [{}])[0].get("commit") or {}).get("statusCheckRollup") or {}
            out.append({
                "box": HOST, "forge": "github.com", "role": role,
                "ref": f'{p["repository"]["nameWithOwner"]}#{p["url"].rsplit("/", 1)[1]}',
                "url": p["url"], "title": p["title"], "draft": p["isDraft"],
                "status": p["reviewDecision"], "conflicts": p["mergeable"] == "CONFLICTING",
                "pipeline": (roll.get("state") or "").lower() or None,
                "unresolved": sum(1 for t in p["reviewThreads"]["nodes"] if not t["isResolved"]),
                "author": p["author"]["login"],
                "updated": p["updatedAt"][:16], "created": p["createdAt"][:10],
            })
except FileNotFoundError:
    pass
except Exception as e:
    out.append({"box": HOST, "forge": "github.com", "error": str(e)})

print(json.dumps(out, ensure_ascii=False))
