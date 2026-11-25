#!/bin/bash
# builder-kit 1.0.6: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# The kit contract: every kit file in this repository is byte for byte the version infra shipped. Run in CI and before
# every pull request: scripts/kit-check.sh [repo dir]   (no network, read-only; exit 0 = holds, 1 = a finding, each printed)
# Infra's merge check runs ITS OWN copy with its own manifest against the PR head (the repo's copies are editable):
#   KIT_MANIFEST=<templates>/templates/builder-kit/.github/kit.sha256 <templates>/.../scripts/kit-check.sh <clone>
# Manifest lines: "<sha256>  <path>" or "<sha256>  <path>  service" (service agents only: may be absent elsewhere).
# Checks: each file in .github/kit.sha256 exists, has its sha256 and carries the version line; scripts are executable;
# python3 is there (always run with -I: never import from the checked tree) and the hooks are wired in
# .claude/settings.json; CLAUDE.md imports the builder rules; CODEOWNERS names the four kit paths and has no
# placeholder left; the PR template has the kit's sections; the old autocommit hook is gone. Warns (does not fail) when CLAUDE.md is over its size budget.
manifest="${KIT_MANIFEST:+$(cd "$(dirname "$KIT_MANIFEST")" && pwd)/$(basename "$KIT_MANIFEST")}"
root="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || { echo "kit-check: not in a git repository" >&2; exit 1; }
cd "$root" || exit 1
manifest="${manifest:-.github/kit.sha256}"; budget=12288; bad=0
fail() { echo "FAIL $*"; bad=1; }
if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum "$1" | cut -d' ' -f1; }; else sha() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi
[ -f "$manifest" ] || { echo "FAIL $manifest missing: install the kit (templates/builder-kit, via infra)"; exit 1; }
version="$(sed -nE '1s/^# builder-kit ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' "$manifest")"
[ -n "$version" ] || { echo "FAIL $manifest: first line must be '# builder-kit X.Y.Z'"; exit 1; }
while read -r want path scope _; do
  case "$want" in ''|'#'*) continue ;; esac
  case "$scope" in '#'*) scope="" ;; esac
  [ -f "$path" ] || { [ "$scope" = service ] || fail "$path: missing"; continue; }
  [ "$(sha "$path")" = "$want" ] || fail "$path: changed (a kit file is never edited here; put it back, propose the change to infra)"
  grep -qF "builder-kit $version" "$path" || fail "$path: no version line 'builder-kit $version'"
  case "$path" in *.sh) [ -x "$path" ] || fail "$path: not executable" ;; esac
done < "$manifest"
s=.claude/settings.json
command -v python3 >/dev/null 2>&1 || fail "python3 needed (it parses $s); install it, the check cannot hold without it"
if [ -f "$s" ] && command -v python3 >/dev/null 2>&1; then
  # Parsed, not grepped: the hook must be a live entry of the right event, and no hook may run an autocommit.
  while IFS= read -r line; do [ -n "$line" ] && fail "$s: $line"; done < <(python3 -I - "$s" <<'PY'
# -I (isolated): no module is imported from the checked repository (cwd), nor from PYTHON* variables. Stdlib only.
import json, sys
try: h = json.load(open(sys.argv[1])).get("hooks", {})
except Exception as e: print(f"not valid JSON ({e})"); sys.exit()
cmds = lambda ev: [k.get("command", "") for e in h.get(ev, []) for k in e.get("hooks", [])]
if not any(c.endswith("/scripts/ledger.sh hook-start") for c in cmds("SessionStart")): print("SessionStart hook 'scripts/ledger.sh hook-start' not wired")
if not any(c.endswith("/.claude/hooks/autosave.sh") for c in cmds("Stop")): print("Stop hook '.claude/hooks/autosave.sh' not wired")
if [c for ev in h for c in cmds(ev) if "autocommit" in c]: print("a hook still runs an autocommit; delete it (autosave.sh replaces it)")
PY
)
elif [ ! -f "$s" ]; then fail "$s: missing (merge templates/builder-kit/settings.hooks.json into it)"; fi
[ -e .claude/hooks/autocommit.sh ] && fail ".claude/hooks/autocommit.sh: the old hook commits on the branch; delete it (autosave.sh replaces it)"
grep -qE '^@\.claude/builder-rules\.md[[:space:]]*$' CLAUDE.md 2>/dev/null || fail "CLAUDE.md: no line '@.claude/builder-rules.md'"
for p in /CLAUDE.md /.claude/ /.github/ /scripts/; do
  grep -qE "^${p}[[:space:]]+@" .github/CODEOWNERS 2>/dev/null || fail ".github/CODEOWNERS: no owner line for $p"
done
t=.github/pull_request_template.md   # not hashed: a repo merges the kit sections into its own template
for h in "## Checks" "## For infra after the merge" "## Learnings for all agents?"; do
  grep -qxF "$h" "$t" 2>/dev/null || fail "$t: no section '$h' (merge the kit's sections into it)"
done
# No literal double brace in this file: the service HOW-TO-START greps a new repo for them and must find none.
grep -qE '[{][{]' .github/CODEOWNERS 2>/dev/null && fail ".github/CODEOWNERS: a template placeholder is left (GitHub rejects it); fill in the owner"
size="$(wc -c < CLAUDE.md 2>/dev/null | tr -d ' ')"
[ "${size:-0}" -le "$budget" ] || echo "WARN CLAUDE.md is $size bytes, over the $budget budget: move procedures into skills, reference into docs/"
[ "$bad" = 0 ] && echo "kit-check: builder-kit $version holds"
exit "$bad"
