#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Portability lint (kit 1.4.0, infra-control#356/#367 item 12): GNU first, BSD fallback. Every script and test runs on the
# Linux CI runner and on the Mac, so a call that exists on only one of them fails here, not on CI after a review round.
#   scripts/portability-check.sh [repo dir]   (read-only, no network; exit 0 = holds, 1 = a finding, each printed as FAIL)
# Reads the git-tracked shell files (*.sh, *.bash, or a sh/bash/zsh shebang) under scripts/, tests/ and .claude/hooks/.
# FAIL on: stat -f / -c / --format, date -v / -j / -d / -r / --date, sed -i without a suffix (sed -i '', sed -i'', bare sed -i, --in-place), base64 -D,
# grep -P, find -printf, a hard /opt/homebrew/{bin,opt,Cellar}/<tool> path (a PATH entry is fine).
# The fix is a helper from scripts/portable.sh (file_owner, file_mode, file_mtime, date_from_epoch, epoch_from_date,
# days_ago, sed_inplace, b64_decode), or `sed -i.bak ... && rm -f <file>.bak`. That file and this lint are not read.
# One escape per line, for a line that must stay (a test stub's text, a macOS-only launchd step): end it with
#   # portable: <reason>
# A full comment line is never a finding. Read line by line: a call split over a `\` continuation is not seen (accepted gap).
root="$(cd "${1:-.}" 2>/dev/null && { git rev-parse --show-toplevel 2>/dev/null || pwd; })" || { echo "FAIL portability-check: no such directory" >&2; exit 1; }
cd "$root" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "FAIL portability-check: python3 needed"; exit 1; }
python3 -I - "$root" <<'PY'
import os, re, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "ls-files", "--", "scripts", "tests", ".claude/hooks"], capture_output=True, text=True, cwd=root).stdout.splitlines()
RULES = [
    (re.compile(r"\bstat\s+(?:-\S+\s+)*(?:-[A-Za-z]*[fc]\b|--(?:format|printf)\b)"), "stat -f/-c differs between BSD and GNU: use file_owner / file_mode / file_mtime"),
    (re.compile(r"\bdate\b[^|;&)]*\s(?:-[A-Za-z]*[vjdr]\b|--(?:date|reference)\b)"), "date -v/-j/-d/-r exists only on one of BSD and GNU: use date_from_epoch / epoch_from_date / days_ago"),
    (re.compile(r"\bsed\b[^|;&]*\s(?:-[A-Za-z]*i(?:''|\"\")?(?:\s|$)|--in-place\b)"), "sed -i without a suffix (BSD needs '' , GNU forbids it): use sed_inplace, or sed -i.bak ... && rm -f <file>.bak"),
    (re.compile(r"\bbase64\s+(?:-\S+\s+)*-D\b"), "base64 -D is BSD only: use b64_decode"),
    (re.compile(r"\bgrep\s+(?:-\S+\s+)*-[A-Za-z]*P"), "grep -P is GNU only: use grep -E or python3"),
    (re.compile(r"\bfind\b[^|;&]*\s-printf\b"), "find -printf is GNU only: use -exec or a loop"),
    (re.compile(r"/opt/homebrew/(?:bin|opt|Cellar)/[A-Za-z]"), "a hard /opt/homebrew path exists only on the Mac: call the tool by name (PATH)"),
]
SHELL = re.compile(r"^#!.*\b(ba|z)?sh\b")
out = []
for f in files:
    if f in ("scripts/portable.sh", "scripts/portability-check.sh"): continue
    p = os.path.join(root, f)
    if not os.path.isfile(p): continue
    try: lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
    except OSError: continue
    if not (f.endswith((".sh", ".bash")) or (lines and SHELL.match(lines[0]))): continue
    for n, l in enumerate(lines, 1):
        s = l.strip()
        if not s or s.startswith("#"): continue
        if re.search(r"#\s*portable:\s*\S", l): continue
        for rx, msg in RULES:
            if rx.search(l):
                out.append(f"FAIL {f}:{n}: {msg}"); break
print("\n".join(out)) if out else None
sys.exit(1 if out else 0)
PY
rc=$?
[ $rc = 0 ] && echo "portability-check: scripts and tests are portable"
exit $rc
