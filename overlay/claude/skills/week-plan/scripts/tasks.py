#!/usr/bin/env python3
"""Open dotpm tasks of Gaming1 (status != done), one line each.

Reads the vault mounted from the Mac. The Obsidian connector stays the source
of truth for writes; this is only a fast read. Usage: tasks.py [--vault PATH]
"""
import pathlib, sys

VAULT = pathlib.Path("/mnt/mac/Users/julien.garciagonzalez/Documents/obsidian/omarchy")
if "--vault" in sys.argv:
    VAULT = pathlib.Path(sys.argv[sys.argv.index("--vault") + 1])
ROOT = VAULT / "Projects/Gaming1"
if not ROOT.is_dir():
    sys.exit(f"vault not mounted: {ROOT} (fall back to the obsidian connector)")

KEYS = ("status", "priority", "due", "start", "updatedAt", "title", "tags")
rows = []
for f in sorted(ROOT.rglob("_tasks/*.md")):
    text = f.read_text(encoding="utf-8", errors="replace")
    if not text.startswith("---"):
        continue
    meta = {}
    for line in text.split("---", 2)[1].splitlines():
        k, sep, v = line.partition(":")
        if sep and k.strip() in KEYS:
            meta[k.strip()] = v.strip().strip('"')
    if meta.get("status", "todo") == "done":
        continue
    rows.append((str(f.relative_to(VAULT)), *(meta.get(k, "") for k in KEYS)))

prio = {"high": 0, "medium": 1, "low": 2}
rows.sort(key=lambda r: (prio.get(r[2], 3), r[3] or "9999"))
print("path\t" + "\t".join(KEYS))
for r in rows:
    print("\t".join(r))
print(f"# {len(rows)} open tasks", file=sys.stderr)
