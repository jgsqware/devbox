#!/usr/bin/env python3
"""My open Jira tickets (gaming-1.atlassian.net via twg), one line each."""
import json, subprocess, sys

JQL = "assignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC, updated DESC"
out = subprocess.run(
    ["twg", "--output", "json", "--output-summary", "none", "jira", "workitem", "query",
     "--jql", JQL, "--fields", "summary,status,priority,duedate,updated,customfield_10020",
     "--limit", "100"],
    capture_output=True, text=True)
if out.returncode:
    sys.exit(f"twg failed: {out.stderr.strip()[:500]}")
issues = json.loads(out.stdout)["data"]["issues"]
print("key\tstatus\tpriority\tdue\tupdated\tsprint\tsummary")
for i in issues:
    sprints = i.get("customfield_10020") or []
    sprint = next((s["name"] for s in sprints if s.get("state") == "active"), sprints[-1]["name"] if sprints else "")
    print("\t".join([i["key"], i["status"]["name"], (i.get("priority") or {}).get("name", ""),
                     i.get("duedate") or "", i["updated"][:10], sprint, i["summary"]]))
print(f"# {len(issues)} open tickets", file=sys.stderr)
