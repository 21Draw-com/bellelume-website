#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Migrate the old shared logs once (kit 1.4.0, infra-control#357/#367 item 4; no legacy path): every tracked DECISIONS.md and
# LEARNINGS.md (any folder, any case), and a TESTING.md that is a dated log (two or more "## YYYY-MM-DD" headings), becomes
# one file per entry; the old file is removed with `git rm` and the new files are `git add`ed, for the same PR.
#   scripts/split-logs.sh [--dry-run]     (--dry-run prints what it would write and changes nothing)
# Entries: each "## " section is one entry (its heading and body, byte for byte). A file without "## " sections but with a
# Markdown table gives one entry per table row (the header names become "- <name>: <value>" lines). Text before the first
# entry (the file's own explanation) goes to docs/<kind>/about.md.
#   decisions -> docs/decisions/NNNN-<slug>.md, numbered oldest first after the highest NNNN already there (a newest-first
#                log, judged from its first and last dated heading, is numbered in reverse)
#   learnings -> docs/learnings/YYYY-MM-DD-<slug>.md (the first date in the heading or the body, else "undated")
#   testing   -> docs/testing/YYYY-MM-DD-<slug>.md (same naming)
# A name already taken gets "-2", "-3". It never overwrites a file. At the end it prints the tables (scripts/docs-index.sh).
# A TESTING.md that is a guide is left alone (hotspot-check only forbids adding dated entries to it).
set -u
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "split-logs: not in a git repository" >&2; exit 2; }
cd "$root" || exit 2
self="$(cd "$(dirname "$0")" && pwd)"
dry=0; case "${1:-}" in --dry-run) dry=1 ;; '') ;; *) echo "usage: split-logs.sh [--dry-run]" >&2; exit 2 ;; esac
command -v python3 >/dev/null 2>&1 || { echo "split-logs: python3 needed" >&2; exit 2; }
python3 -I - "$root" "$dry" <<'PY' || exit 1
import os, re, subprocess, sys
root, dry = sys.argv[1], sys.argv[2] == "1"
git = lambda *a: subprocess.run(["git", "-c", "core.quotePath=false", *a], cwd=root, check=True, capture_output=True, text=True).stdout
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
DATED = re.compile(r"^#{2,4}\s+\d{4}-\d{2}-\d{2}", re.M)
def slug(t):
    t = DATE.sub("", t); t = re.sub(r"[^A-Za-z0-9]+", "-", t.lower()).strip("-")
    return (t[:60].rstrip("-") or "entry")
def sections(text):
    """(preamble, [entry text]) by '## ' headings; else by table rows; else no entries."""
    parts = re.split(r"(?m)^(?=## )", text)
    if len(parts) > 1:
        return parts[0], parts[1:]
    lines = text.splitlines(keepends=True)
    for i in range(len(lines) - 1):
        if lines[i].lstrip().startswith("|") and re.fullmatch(r"\s*\|?(\s*:?-{3,}:?\s*\|)+\s*:?-*:?\s*\|?\s*", lines[i + 1].rstrip("\n")):
            head = [c.strip() for c in lines[i].strip().strip("|").split("|")]
            j, rows = i + 2, []
            while j < len(lines) and lines[j].lstrip().startswith("|"):
                cells = [c.strip() for c in lines[j].strip().strip("|").split("|")]
                title = " ".join(c for c in cells[:3] if c and not DATE.fullmatch(c))[:120] or "entry"
                body = "".join(f"- {h or 'col'}: {c}\n" for h, c in zip(head, cells))
                rows.append(f"## {title}\n\n{body}"); j += 1
            pre = "".join(lines[:i]) + "".join(lines[j:])
            return pre, rows
    return text, []
files = [f for f in git("ls-files", "-z").split("\0") if f]
plan, removed = [], []
taken = set()
def free(path):
    b, n = path[:-3], 2
    while os.path.exists(os.path.join(root, path)) or path in taken:
        path = f"{b}-{n}.md"; n += 1
    taken.add(path); return path
for f in sorted(files):
    base = os.path.basename(f).lower()
    kind = {"decisions.md": "decisions", "learnings.md": "learnings", "testing.md": "testing"}.get(base)
    if not kind: continue
    p = os.path.join(root, f)
    if os.path.islink(p) or not os.path.isfile(p): continue
    text = open(p, encoding="utf-8").read()
    if kind == "testing" and len(DATED.findall(text)) < 2: continue        # a guide stays
    pre, entries = sections(text)
    if not entries:
        print(f"split-logs: {f}: no '## ' entries and no table: split it by hand", file=sys.stderr); sys.exit(1)
    d = f"docs/{kind}"
    kept = [l for l in pre.splitlines() if l.strip()]
    if kept and not (len(kept) == 1 and kept[0].startswith("# ")):      # more than a bare title: keep the explanation
        plan.append((free(f"{d}/about.md"), f"<!-- from {f} -->\n" + pre))
    if kind == "decisions":
        dates = [m.group(0) for e in entries for m in [DATE.search(e.splitlines()[0])] if m]
        if len(dates) >= 2 and dates[0] > dates[-1]: entries = entries[::-1]
        have = [int(x[:4]) for x in os.listdir(os.path.join(root, d)) if re.match(r"\d{4}-", x)] if os.path.isdir(os.path.join(root, d)) else []
        have += [int(os.path.basename(x)[:4]) for x, _ in plan if x.startswith(d + "/") and re.match(r"\d{4}-", os.path.basename(x))]
        n = max(have, default=0)
        for e in entries:
            n += 1; plan.append((free(f"{d}/{n:04d}-{slug(e.splitlines()[0][3:])}.md"), e))
    else:
        for e in entries:
            m = DATE.search(e.splitlines()[0]) or DATE.search(e)
            plan.append((free(f"{d}/{m.group(0) if m else 'undated'}-{slug(e.splitlines()[0][3:])}.md"), e))
    removed.append(f)
if not removed:
    print("split-logs: nothing to migrate (no DECISIONS.md, LEARNINGS.md or dated TESTING.md log)"); sys.exit(0)
for path, body in plan:
    print(("would write " if dry else "wrote ") + path)
    if not dry:
        os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        with open(os.path.join(root, path), "x", encoding="utf-8") as fh: fh.write(body if body.endswith("\n") else body + "\n")
for f in removed:
    print(("would remove " if dry else "removed ") + f)
if not dry:
    git("add", "--", *[p for p, _ in plan]); git("rm", "-q", "--", *removed)
PY
[ "$dry" = 1 ] && exit 0
for k in decisions learnings testing; do [ -d "docs/$k" ] && { echo; echo "docs/$k:"; bash "$self/docs-index.sh" "$k"; }; done
exit 0
