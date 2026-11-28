#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Pre-flight (kit 1.4.0, infra-control#367 items 7 + 19): the deterministic checks a reviewer must never redo, run by the
# builder before a PR is labelled ready. Rule: label `infra-review` only on a green pre-flight (`--label` does it for you).
#   scripts/preflight.sh <PR number> [--label]     reads the PR body and size with gh (read only; --label adds the label when green)
#   scripts/preflight.sh --body-file <file>        the same without gh, for a body not yet on GitHub (size from git)
# Steps, all run, each printed:
#   1. scripts/kit-check.sh: the kit files, workflow-check, test register, portability-check, hotspot-check (KIT_BASE passes through)
#   2. the repo's quick tests: scripts/quick-tests.sh (the repo's own file, not a kit file: its tier=quick tests from
#      .github/test-register.txt; `exit 0` with a comment when the repository has no tests). Missing: red.
#   0. (with a PR number) this checkout's HEAD is the PR's head sha, else red: the checks ran on another commit
#   3. the PR body has the four blocks, each filled in: "## Checks", "## For Renco", "## For infra after the merge",
#      "## Learnings for all agents?" (a block with only a <placeholder> or nothing counts as missing; "nothing"/"no" is fine)
#   4. size: WARN (never red) above 40 files or 1500 changed lines: split the PR if it can be split.
# Exit 0 = green, 1 = red, 2 = usage. It RUNS the repository's own scripts/quick-tests.sh: a builder's tool for its own
# branch, never something infra runs on an untrusted clone (infra runs its own kit-check copy with KIT_STRICT=1 KIT_BASE=<sha>).
set -u
self="$(cd "$(dirname "$0")" && pwd)"   # before any cd: $0 may be relative
die() { echo "preflight: $*" >&2; exit 2; }
pr=""; body_file=""; label=0
while [ $# -gt 0 ]; do
  case "$1" in
    --label) label=1 ;;
    --body-file) [ $# -ge 2 ] || die "--body-file needs a file"; body_file="$2"; case "$body_file" in /*) ;; *) body_file="$PWD/$body_file" ;; esac; shift ;;
    [1-9]*) [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "odd PR number"; pr="$1" ;;
    *) die "usage: preflight.sh <PR number> [--label] | --body-file <file>" ;;
  esac; shift
done
{ [ -n "$pr" ] || [ -n "$body_file" ]; } || die "usage: preflight.sh <PR number> [--label] | --body-file <file>"
{ [ -n "$pr" ] && [ -n "$body_file" ]; } && die "give a PR number or --body-file, not both"
[ "$label" = 1 ] && [ -z "$pr" ] && die "--label needs a PR number"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repository"
cd "$root" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 needed"; exit 1; }
red=0; step() { echo "== $1"; }
step "1/4 kit-check"
bash "$self/kit-check.sh" "$root" || red=1
step "2/4 quick tests (scripts/quick-tests.sh)"
if [ -x scripts/quick-tests.sh ]; then scripts/quick-tests.sh || { echo "FAIL quick tests are red"; red=1; }
else echo "FAIL scripts/quick-tests.sh missing or not executable: the repo's tier=quick tests (exit 0 with a comment when it has none)"; red=1; fi
step "3/4 PR body blocks"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
files=""; lines=""
if [ -n "$pr" ]; then
  command -v gh >/dev/null 2>&1 || { echo "FAIL gh needed to read PR #$pr (or use --body-file)"; exit 1; }
  gh pr view "$pr" --json body,changedFiles,additions,deletions,headRefOid > "$tmp" || { echo "FAIL gh could not read PR #$pr"; exit 1; }
  head_oid="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"])' "$tmp")"
  [ "$head_oid" = "$(git rev-parse HEAD)" ] || { echo "FAIL PR #$pr head is ${head_oid:0:12}, this checkout is $(git rev-parse --short=12 HEAD): push, or check out the PR's branch (the checks above ran on the wrong commit)"; red=1; }
  read -r files lines < <(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["changedFiles"], d["additions"]+d["deletions"])' "$tmp")
  python3 -I -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))["body"] or "")' "$tmp" > "$tmp.body"; mv "$tmp.body" "$tmp"
else
  [ -f "$body_file" ] || die "no such file: $body_file"
  cp "$body_file" "$tmp"
fi
python3 -I - "$tmp" <<'PY' || red=1
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read().replace("\r", "")
need = ["## Checks", "## For Renco", "## For infra after the merge", "## Learnings for all agents?"]
heads = [(m.start(), m.group(0).strip()) for m in re.finditer(r"(?m)^##\s+.*$", text)]
bad = False
for h in need:
    hit = [i for i, (pos, t) in enumerate(heads) if t == h]
    if not hit:
        print(f"FAIL PR body: no block '{h}'"); bad = True; continue
    i = hit[0]; start = heads[i][0] + len(heads[i][1]); end = heads[i + 1][0] if i + 1 < len(heads) else len(text)
    body = re.sub(r"<!--.*?-->", "", text[start:end], flags=re.S)
    filled = [l for l in body.splitlines() if l.strip() and not re.fullmatch(r"\s*(-\s*)?<[^>]*>\s*", l)]
    if h == "## Checks" and re.search(r"small \| normal \| risky|<command>|<findings and what I did", body):
        print("FAIL PR body: block '## Checks' still has template text (choose the tier, fill in the test command and the reviewer lines)"); bad = True; continue
    if not filled:
        print(f"FAIL PR body: block '{h}' is empty or only a <placeholder> (write 'nothing' or 'no' when that is the answer)"); bad = True
if not bad: print("PR body: the four blocks are filled in")
sys.exit(1 if bad else 0)
PY
step "4/4 size"
if [ -z "$files" ]; then
  def="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  b="${KIT_BASE:-$(git merge-base HEAD "$def" 2>/dev/null)}"
  if [ -n "$b" ]; then
    files="$(git diff --name-only "$b" HEAD | wc -l | tr -d ' ')"
    lines="$(git diff --numstat "$b" HEAD | awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }')"
  fi
fi
if [ -z "$files" ]; then echo "NOTE size not measured (no base; set KIT_BASE)"
elif [ "$files" -gt 40 ] || [ "$lines" -gt 1500 ]; then echo "WARN large PR: $files files, $lines changed lines (over 40 files or 1500 lines): split it if it can be split; not a block"
else echo "size: $files files, $lines changed lines"; fi
if [ "$red" = 0 ]; then
  echo "preflight: GREEN"
  if [ "$label" = 1 ]; then
    gh pr edit "$pr" --add-label infra-review >/dev/null 2>&1 || { gh label create infra-review >/dev/null 2>&1; gh pr edit "$pr" --add-label infra-review >/dev/null; } \
      && echo "label infra-review added to #$pr" || { echo "FAIL could not add the label infra-review"; exit 1; }
  fi
  exit 0
fi
echo "preflight: RED: fix the FAIL lines above, then run it again (no infra-review label on a red pre-flight)"
exit 1
