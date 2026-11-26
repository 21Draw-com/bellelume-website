#!/bin/bash
# builder-kit 1.3.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Test register check (kit 1.3.0, infra-control#354, plan docs/plans/2026-11-27-ci-test-value.md §2): every folder with tests is
# covered by the register `.github/test-register.txt`, and every `protects` names an issue.
#   scripts/test-register-check.sh [repo dir]     (read-only; exit 0 = holds, 1 = a finding, each printed as FAIL)
# Format, one line per folder (a folder line covers its subfolders; the longest match wins), `#` starts a comment:
#   <folder>  kind=<unit|contract|integration|e2e|security|architecture>  tier=<quick|middle|full>  protects=<#N | owner/repo#N>
# An exception is one line for one test, id = <path>::<name> (with the parameter case: tests/t.py::test_x[case1]):
#   tests/test_pay.py::test_refund[eu]  kind=integration  tier=full  protects=#41
# A "test folder" is a git-tracked folder with test_*.py, *_test.py, *.test.* or *.spec.* (ts, tsx, js, jsx, mjs).
# Offline by default: the ids are checked for form only. With KIT_REGISTER_ONLINE=1 each id must
# also exist: `gh issue view` on the repo (a bare #N means this repository's origin). No per-test headers anywhere.
root="$(cd "${1:-.}" 2>/dev/null && { git rev-parse --show-toplevel 2>/dev/null || pwd; })" || { echo "FAIL test-register-check: no such directory" >&2; exit 1; }
cd "$root" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "FAIL test-register-check: python3 needed"; exit 1; }
slug=""
if [ "${KIT_REGISTER_ONLINE:-}" = 1 ]; then
  slug="$(git remote get-url origin 2>/dev/null | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##')"
fi
python3 -I - "$root" "${KIT_REGISTER_ONLINE:-}" "$slug" <<'PY'
import os, re, subprocess, sys
root, online, slug = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
KINDS = {"unit", "contract", "integration", "e2e", "security", "architecture"}
TIERS = {"quick", "middle", "full"}
TEST = re.compile(r"(^test_.*\.py$|.*_test\.py$|.*\.(test|spec)\.(ts|tsx|js|jsx|mjs)$)")
out, bad = [], False
def fail(m):
    global bad; bad = True; out.append("FAIL " + m)
files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=root).stdout.splitlines()
folders = sorted({os.path.dirname(f) or "." for f in files if TEST.match(os.path.basename(f))})
reg = ".github/test-register.txt"
if not folders:
    print("test-register-check: no test folders, no register needed"); sys.exit(0)
if not os.path.isfile(os.path.join(root, reg)):
    print(f"FAIL {reg}: missing ({len(folders)} test folder(s): {', '.join(folders[:5])}); one line per folder, format in scripts/test-register-check.sh"); sys.exit(1)
entries, ids = {}, set()
for n, line in enumerate(open(os.path.join(root, reg), encoding="utf-8", errors="replace").read().splitlines(), 1):
    s = re.sub(r"(^|\s)#(?!\d).*$", "", line).strip()
    if not s: continue
    parts = s.split()
    path, kv = parts[0], {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        kv[k] = v
    if set(kv) != {"kind", "tier", "protects"} or len(parts) != 4:
        fail(f"{reg}:{n}: needs exactly path kind=.. tier=.. protects=.. ({s[:60]})"); continue
    if kv["kind"] not in KINDS: fail(f"{reg}:{n}: kind `{kv['kind']}` not one of {sorted(KINDS)}")
    if kv["tier"] not in TIERS: fail(f"{reg}:{n}: tier `{kv['tier']}` not one of {sorted(TIERS)}")
    if not re.fullmatch(r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[1-9][0-9]*", kv["protects"]):
        fail(f"{reg}:{n}: protects `{kv['protects']}` is not an issue id (#N or owner/repo#N)")
    else: ids.add(kv["protects"])
    p = path.split("::", 1)[0].rstrip("/") or "."
    if p != "." and not any(f == p or f.startswith(p + "/") for f in files): fail(f"{reg}:{n}: `{p}` is not a tracked path (stale line)")
    if "::" in path:
        if p not in files: fail(f"{reg}:{n}: an exception line names a test file: `{path}`")
    else: entries[p] = n
for d in folders:
    if not any(e == "." or d == e or d.startswith(e + "/") for e in entries): fail(f"{reg}: test folder `{d}` has no line")
if online:
    for i in sorted(ids):
        repo, num = (i.split("#")[0] or slug), i.split("#")[1]
        r = subprocess.run(["gh", "issue", "view", num, "--repo", repo, "--json", "number"], capture_output=True, text=True, timeout=30) if repo else None
        if r is None or r.returncode != 0: fail(f"{reg}: protects {i} does not exist (or gh cannot read it)")
print("\n".join(out))
if not bad: print("test-register-check: every test folder is registered" + (" and every id exists" if online else " (ids checked for form only)"))
sys.exit(1 if bad else 0)
PY
