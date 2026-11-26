#!/bin/bash
# builder-kit 1.0.9: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Builder ledger: this repository's own work as a dependency tree that survives any restart (infra-control#149).
# A kit file infra ships; the same file in every builder repo.
# Two layers, no second source of truth:
#   facts  ~/.cache/builder-ledger/<owner>__<repo>.json  open issues + PRs + blocked_by (with the live state of every
#          external blocker), one GraphQL query, rebuilt from GitHub at each trigger, never in git
#   notes  <git common dir>/builder-ledger/notes.json  only what GitHub cannot say: `next` step, `waits_on`, state, notes;
#          one store for the main clone and every worktree, never in the tree, never committed (kit 1.0.5)
# Read-only towards GitHub. Never polls: it runs at session start (hook), before a plan, after a merge, by hand.
#   ledger.sh show                 can start now (by stream) | waiting on | merged, not verified | decisions waiting | PRs
#   ledger.sh hygiene              the check, numbers only, green/amber/red; infra reads the same table
#   ledger.sh overview             show + job sessions + hygiene: the facts for the skill status-overview
#   ledger.sh rebuild              refresh the facts
#   ledger.sh note <#n|owner/repo#n> <text>        dated note on an item (creates it)
#   ledger.sh set <ref> next <text> | state open|waiting|merged-unverified|verified | waits_on <list>|- | from_renco true|false
#       waits_on takes issue refs (cross-organisation blockers GitHub cannot link) and named parties: renco, infra, <builder>
#   ledger.sh verify <ref> <what you saw live>     leave merged-unverified
#   ledger.sh hook-start | hook-prompt             the Claude hooks: bounded (8 s with a cache, 30 s without), fail-soft, always exit 0,
#       read-only towards the tree (no archiving: that happens only in rebuild/note/set/verify)
export LEDGER_ROOT="${LEDGER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PY="$(cat <<'PYEOF'
import json, os, re, sys, subprocess, time, datetime as dt

ROOT = os.environ["LEDGER_ROOT"]
CACHE = os.environ.get("LEDGER_CACHE", os.path.expanduser("~/.cache/builder-ledger"))
NOW = dt.datetime.now(dt.timezone.utc)
STATES = ("open", "waiting", "merged-unverified", "verified")

def iso(t=None): return (t or NOW).strftime("%Y-%m-%dT%H:%M:%SZ")
def hours(s): return (NOW - dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)).total_seconds() / 3600
def clip(s, n): s = " ".join(str(s).split()); return s if len(s) <= n else s[:n - 1] + "…"
def load(p, d):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return d
def save(p, data):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".tmp", "w") as f: json.dump(data, f, indent=1, ensure_ascii=False); f.write("\n")
    os.replace(p + ".tmp", p)
def run(cmd, t=10): return subprocess.run(cmd, capture_output=True, text=True, timeout=t, cwd=ROOT)

def slug():
    u = run(["git", "remote", "get-url", "origin"]).stdout.strip()
    m = re.search(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?$", u)
    if not m: sys.exit("ledger: no GitHub origin")
    return m.group(1)
SLUG = slug(); FACTS = os.path.join(CACHE, SLUG.replace("/", "__") + ".json")

def store():
    g = run(["git", "rev-parse", "--git-common-dir"]).stdout.strip()
    if not g: sys.exit("ledger: not a git checkout")
    return os.path.join(os.path.abspath(os.path.join(ROOT, g)), "builder-ledger", "notes.json")
NOTES = store()
OLD = os.path.join(ROOT, "docs", "work-ledger.json")    # kit <= 1.0.3 kept the notes in the tree: migrated once, then `git rm` it

def migrate():
    """One time: first run with no store yet and the old tracked file present -> copy its content into the store.
    The tracked file is never touched (the install PR `git rm`s it); once the store exists this is never looked at again."""
    if os.path.exists(NOTES) or not os.path.exists(OLD): return
    old = load(OLD, None)
    if isinstance(old, dict): save(NOTES, old)

def archive_closed(n):
    """Closed issue -> archive (not while merged-unverified). Only called from rebuild/note/set/verify, never from a hook."""
    f = load(FACTS, None)
    if not f: return False
    ch = False
    for k in list(n["items"]):
        if k.startswith(SLUG + "#") and k.rsplit("#", 1)[1] not in f["issues"] and n["items"][k]["state"] != "merged-unverified":
            n["archive"][k] = dict(n["items"].pop(k), archived=iso()[:10]); ch = True
    return ch

def notes():
    migrate()
    n = load(NOTES, {})
    n.setdefault("about", "This builder's notes layer of the ledger: only what GitHub cannot say. Facts are rebuilt from GitHub (scripts/ledger.sh rebuild). Edit only via scripts/ledger.sh note|set|verify.")
    n.setdefault("items", {}); n.setdefault("archive", {})
    return n
def ref(t):
    m = re.fullmatch(r"(?:([\w.-]+/[\w.-]+))?#?(\d+)", t.strip()) if "#" not in t else re.fullmatch(r"(?:([\w.-]+/[\w.-]+))?#(\d+)", t.strip())
    if not m: sys.exit(f"bad reference {t!r}: use #n or owner/repo#n")
    return f"{m.group(1) or SLUG}#{m.group(2)}"
def local(key): return key.rsplit("#", 1)[1] if key.startswith(SLUG + "#") else key

Q = """query($o:String!,$n:String!,$ic:String,$pc:String){repository(owner:$o,name:$n){
issues(states:OPEN,first:100,after:$ic){pageInfo{hasNextPage endCursor}nodes{number title createdAt updatedAt labels(first:10){nodes{name}}
 blockedBy(first:10){nodes{number state repository{nameWithOwner}}}}}
pullRequests(states:OPEN,first:100,after:$pc){pageInfo{hasNextPage endCursor}nodes{number title headRefName createdAt updatedAt isDraft reviewDecision
 closingIssuesReferences(first:10){nodes{number}}}}}}"""

class Slow(Exception): pass

def rebuild(budget=30, heal=False):
    o, nm = SLUG.split("/"); issues, prs, ic, pc, more = {}, {}, None, None, True
    end = time.time() + budget
    while more:
        cmd = ["gh", "api", "graphql", "-f", "query=" + Q, "-f", "o=" + o, "-f", "n=" + nm] + (["-f", "ic=" + ic] if ic else []) + (["-f", "pc=" + pc] if pc else [])
        try: r = run(cmd, max(1, end - time.time()))
        except subprocess.TimeoutExpired: raise Slow("no answer within the budget")
        try: d = json.loads(r.stdout)["data"]["repository"]
        except Exception: raise Slow((r.stderr.strip() or "no answer from GitHub")[:80])
        for i in d["issues"]["nodes"]:
            issues[str(i["number"])] = {"title": i["title"], "updated": i["updatedAt"], "labels": [l["name"] for l in i["labels"]["nodes"]],
                "blocked_by": [{"ref": f'{b["repository"]["nameWithOwner"]}#{b["number"]}', "state": b["state"]} for b in i["blockedBy"]["nodes"]]}
        for p in d["pullRequests"]["nodes"]:
            prs[str(p["number"])] = {"title": p["title"], "branch": p["headRefName"], "created": p["createdAt"], "updated": p["updatedAt"], "draft": p["isDraft"],
                "review": p["reviewDecision"], "closes": [str(c["number"]) for c in p["closingIssuesReferences"]["nodes"]]}
        ic = d["issues"]["pageInfo"]["endCursor"] if d["issues"]["pageInfo"]["hasNextPage"] else None
        pc = d["pullRequests"]["pageInfo"]["endCursor"] if d["pullRequests"]["pageInfo"]["hasNextPage"] else None
        more = bool(ic or pc)
    facts = {"built": iso(), "issues": issues, "prs": prs}; save(FACTS, facts)
    if heal:
        n = notes()
        if archive_closed(n): save(NOTES, n)
    return facts

def facts_or_build():
    f = load(FACTS, None)
    return f if f else rebuild()

def cache_note(why):
    f = load(FACTS, None)
    return f"ledger: GitHub slow ({why}), showing the cache from {f['built'][:16]}" if f else "ledger: no cache yet and GitHub did not answer in time, run `scripts/ledger.sh rebuild` again"


def analyse():
    n = notes(); f = facts_or_build(); issues = f["issues"]
    def blockers(num):
        """open blockers of an issue: GitHub blocked_by (live state) + notes waits_on (issues and named parties)"""
        out = {}
        for b in issues.get(num, {}).get("blocked_by", []):
            if b["state"] == "OPEN": out[b["ref"]] = "open issue"
        for w in n["items"].get(f"{SLUG}#{num}", {}).get("waits_on", []):
            if "#" in w:
                if w.startswith(SLUG + "#"):
                    if w.rsplit("#", 1)[1] in issues: out[w] = "open issue"
                else: out[w] = "other repo, state unknown (waits_on)"
            else: out[w] = "person/agent"
        return out
    return n, f, blockers

def sections():
    n, f, blockers = analyse(); issues, prs = f["issues"], f["prs"]
    with_pr = {c for p in prs.values() for c in p["closes"]}
    ready, waits, decide = [], [], []
    for num in sorted(issues, key=int):
        it = n["items"].get(f"{SLUG}#{num}", {}); b = blockers(num)
        t = f"#{num} {clip(issues[num]['title'], 60)}"
        if b:
            waits.append(f"{t}  WAITS ON  " + "; ".join(f"{k} ({v})" for k, v in b.items()))
            if any(k in ("renco",) for k in b): decide.append(t)
        elif num in with_pr: continue
        else: ready.append(t + (f"  -> {clip(it['next'], 60)}" if it.get("next") else ""))
    S = {}
    S["MERGED, NOT VERIFIED (leave with: ledger.sh verify <ref> <what you saw>)"] = [f"{local(k)} {clip(v.get('next') or (v['notes'] or [''])[-1], 70)}" for k, v in n["items"].items() if v["state"] == "merged-unverified"]
    S[f"CAN START NOW ({len(ready)}): every blocker is closed; independent items start side by side, each in its own job session (scripts/job-session.sh)"] = ready
    S["WAITING ON (blocker, with its live state)"] = waits
    S["DECISIONS WAITING FOR RENCO"] = decide
    S["OPEN PRs"] = [f"#{k} {clip(p['title'], 55)}  [{int(hours(p['created']))} h old, {'draft' if p['draft'] else (p['review'] or 'no review yet').lower()}]" for k, p in prs.items()]
    return S

def show(brief=False):
    f = facts_or_build()
    print(f"ledger {SLUG}: facts {f['built'][:16]}, {len(f['issues'])} open issues, {len(f['prs'])} open PRs")
    for title, rows in sections().items():
        if not rows or (brief and title.startswith(("WAITING", "OPEN"))): continue
        print(f"{title} [{len(rows)}]")
        for r in rows[: 6 if brief else 80]: print("  " + r)
        if brief and len(rows) > 6: print(f"  +{len(rows) - 6} more (scripts/ledger.sh show)")

def hygiene():
    n, f, blockers = analyse(); issues, prs = f["issues"], f["prs"]
    with_pr = {c for p in prs.values() for c in p["closes"]}
    no_next = [k for k in issues if not blockers(k) and k not in with_pr and not n["items"].get(f"{SLUG}#{k}", {}).get("next")]
    stale = [k for k, i in issues.items() if hours(i["updated"]) > 168]
    slow_pr = [k for k, p in prs.items() if hours(p["updated"]) > 24 and not p["draft"]]
    unver = [k for k, v in n["items"].items() if v["state"] == "merged-unverified"]
    hook = False
    for fn in (".claude/settings.json", ".claude/settings.local.json"):
        try: hook = hook or "ledger.sh hook-start" in open(os.path.join(ROOT, fn)).read()
        except OSError: pass
    adopted = hook or os.path.exists(NOTES)
    def rag(x, amber, red): return "green" if x < amber else ("amber" if x < red else "red")
    rows = [("open issues without next step or blocker", len(no_next), rag(len(no_next), 1, 4)),
            ("open issues untouched > 7 days", len(stale), rag(len(stale), 1, 4)),
            ("PRs open > 24 h with no move", len(slow_pr), rag(len(slow_pr), 1, 3)),
            ("merged, not verified (verify each in the live system)", len(unver), rag(len(unver), 1, 3)),
            ("ledger adopted (SessionStart hook or notes store)", 0 if adopted else 1, "green" if adopted else "red")]
    print(f"hygiene {SLUG}")
    for t, c, r in rows: print(f"  {r:6} {c:3}  {t}")
    for lbl, lst in (("no next", no_next), ("untouched", stale), ("slow PRs", slow_pr)):
        if lst: print(f"    {lbl}: " + ", ".join("#" + k for k in lst[:12]) + (" …" if len(lst) > 12 else ""))
    return max((r for _, _, r in rows), key=["green", "amber", "red"].index)

def overview():
    show()
    print("JOB SESSIONS (scripts/job-session.sh list):")
    r = run(["bash", os.path.join(ROOT, "scripts", "job-session.sh"), "list"]) if os.path.exists(os.path.join(ROOT, "scripts", "job-session.sh")) else None
    print("  " + (r.stdout.strip().replace("\n", "\n  ") if r and r.stdout.strip() else "none running"))
    hygiene()

def item(n, key): return n["items"].setdefault(key, {"from_renco": False, "state": "open", "next": "", "waits_on": [], "notes": []})
def stamp(): return dt.datetime.now().strftime("%Y-%m-%d %H:%M")
def main(a):
    c, r = (a + [""])[0], a[1:]
    if c == "rebuild":
        f = rebuild(heal=True); print(f"ledger: {len(f['issues'])} open issues, {len(f['prs'])} open PRs")
    elif c == "show": show()
    elif c == "hygiene": hygiene()
    elif c == "overview": overview()
    elif c == "note":
        n = notes(); item(n, ref(r[0]))["notes"].append(f"{stamp()} {' '.join(r[1:])}"); archive_closed(n); save(NOTES, n)
    elif c == "set":
        if len(r) < 3: sys.exit("usage: set <ref> next|state|waits_on|from_renco <value>")
        n = notes(); it = item(n, ref(r[0])); fld, val = r[1], " ".join(r[2:])
        if fld == "state":
            if val not in STATES: sys.exit(f"state must be one of {STATES}")
            it[fld] = val
        elif fld == "next": it[fld] = val
        elif fld == "from_renco": it[fld] = val.lower() in ("true", "yes", "1")
        elif fld == "waits_on": it[fld] = [] if val == "-" else [ref(x) if "#" in x else x.strip() for x in val.split(",") if x.strip()]
        else: sys.exit("fields: next, state, waits_on, from_renco")
        archive_closed(n); save(NOTES, n)
    elif c == "verify":
        n = notes(); it = item(n, ref(r[0])); it["state"] = "verified"; it["notes"].append(f"{stamp()} verified: {' '.join(r[1:])}"); archive_closed(n); save(NOTES, n)
    elif c == "hook-start":
        have = os.path.exists(FACTS)                  # with a cache the start stays quick; without one it may take the full budget
        try: rebuild(budget=8 if have else 30)
        except Exception as e: print(cache_note(str(e)[:60]))
        if os.path.exists(FACTS): show(brief=True)
    elif c == "hook-prompt": print("ledger: a new task? Issue first, then `scripts/ledger.sh note <#n> <text>` and `set <#n> next <text>`.")
    else: sys.exit("usage: ledger.sh show|hygiene|overview|rebuild|note|set|verify (see the header of this file)")
try: main(sys.argv[1:])
except Slow as e: sys.exit(cache_note(str(e)[:60]))
except subprocess.TimeoutExpired: sys.exit(cache_note("timeout"))
PYEOF
)"
case "${1:-}" in
  hook-start|hook-prompt) python3 -I -c "$PY" "$@" 2>/dev/null; exit 0 ;;   # a hook never blocks, never fails
esac
exec python3 -I -c "$PY" "$@"
