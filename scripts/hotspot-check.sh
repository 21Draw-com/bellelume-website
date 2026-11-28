#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Hotspot check (kit 1.4.0, infra-control#357/#367 item 4): parallel PRs that append to one shared file conflict with each
# other on every merge. One file per entry instead: docs/decisions/NNNN-<slug>.md, docs/testing/<slug>.md,
# docs/learnings/YYYY-MM-DD-<slug>.md (tables: scripts/docs-index.sh, never committed). Migrated once, no legacy path:
#   scripts/hotspot-check.sh [repo dir]   (read-only, no network; exit 0 = holds, 1 = a finding, each printed as FAIL)
# On the tree (no base needed):
#   - a tracked DECISIONS.md or LEARNINGS.md (any folder, any letter case) FAILS: split it with scripts/split-logs.sh
#   - a tracked TESTING.md that is a dated log (two or more "## YYYY-MM-DD" headings) FAILS the same way; a TESTING.md that
#     is a guide stays a guide
# Against the base (what this branch adds):
#   - a TESTING.md that gains a dated heading ("#.. YYYY-MM-DD") FAILS: a test note is its own file in docs/testing/
#   - a README.md or INDEX.md in docs/decisions, docs/testing or docs/learnings that grows FAILS (the index is generated)
# The base: KIT_BASE=<rev> if set; else, in a pull_request run (GITHUB_BASE_REF set), origin/$GITHUB_BASE_REF, or HEAD^1
# when the checkout is GitHub's merge commit (fetch-depth: 2 is enough); else the merge base with origin's default branch.
# On the default branch itself there is nothing to compare: the tree checks still run. A PR run without a base FAILS
# (no fail-open): fetch the base (actions/checkout with fetch-depth: 2, or 0). KIT_STRICT=1 (infra's merge check, which also
# passes KIT_BASE=<the PR's base sha>) turns every "nothing to compare" into a FAIL.
root="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || { echo "FAIL hotspot-check: not in a git repository" >&2; exit 1; }
cd "$root" || exit 1
bad=0
DATED='#{2,4}[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}'
# --- the tree: no old shared log is left (-z, quotePath off: any file name arrives verbatim)
while IFS= read -r -d '' path; do
  low="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    decisions.md|*/decisions.md|learnings.md|*/learnings.md)
      echo "FAIL $path: an old shared log (a merge-conflict hotspot): migrate it once with scripts/split-logs.sh (one file per entry, the old file deleted in the same PR)"; bad=1 ;;
    testing.md|*/testing.md)
      if [ -f "$path" ] && [ ! -L "$path" ] && [ "$(grep -cE "^$DATED" "$path")" -ge 2 ]; then
        echo "FAIL $path: a dated test log (a merge-conflict hotspot): split it with scripts/split-logs.sh into docs/testing/; a guide stays, its log entries go"; bad=1
      fi ;;
  esac
done < <(git -c core.quotePath=false ls-files -z)
# --- the base
rev() { git rev-parse -q --verify "$1^{commit}" 2>/dev/null; }
base=""; how=""; skip=""
if [ -n "${KIT_BASE:-}" ]; then
  base="$(rev "$KIT_BASE")" || { echo "FAIL hotspot-check: KIT_BASE=$KIT_BASE is not a commit here"; exit 1; }; how="KIT_BASE"
elif [ -n "${GITHUB_BASE_REF:-}" ]; then
  if b="$(rev "origin/$GITHUB_BASE_REF")"; then base="$(git merge-base HEAD "$b" 2>/dev/null)"; how="origin/$GITHUB_BASE_REF"; fi
  if [ -z "$base" ] && [ "$(git rev-list --parents -n1 HEAD 2>/dev/null | wc -w | tr -d ' ')" = 3 ] && b="$(rev HEAD^1)"; then base="$b"; how="the merge commit's base"; fi
  [ -n "$base" ] || { echo "FAIL hotspot-check: pull_request run without its base: give actions/checkout fetch-depth: 2 (or 0)"; exit 1; }
else
  def="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$def" ] || for c in origin/main origin/master; do rev "$c" >/dev/null && { def="$c"; break; }; done
  cur="$(git symbolic-ref -q --short HEAD 2>/dev/null)"
  if [ -z "$def" ]; then skip="no origin default branch here"
  elif [ "origin/$cur" = "$def" ]; then skip="on the default branch"
  else base="$(git merge-base HEAD "$def" 2>/dev/null)" || { echo "FAIL hotspot-check: no merge base with $def (fetch it)"; exit 1; }; how="$def"; fi
fi
if [ -n "$skip" ]; then
  if [ "${KIT_STRICT:-}" = 1 ]; then echo "FAIL hotspot-check: $skip and KIT_STRICT=1: set KIT_BASE=<base sha>"; exit 1; fi
  echo "hotspot-check: $skip, nothing to compare (tree checked; set KIT_BASE to compare)"
else
  # -a (text): a `-diff`/`binary` attribute cannot hide the counts; a `-` is a finding, never a skip.
  while IFS= read -r -d '' rec; do
    add="${rec%%$'\t'*}"; rest="${rec#*$'\t'}"; del="${rest%%$'\t'*}"; path="${rest#*$'\t'}"
    low="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
    case "$low" in
      testing.md|*/testing.md) kind=guide ;;
      docs/decisions/readme.md|docs/decisions/index.md|docs/testing/readme.md|docs/testing/index.md|docs/learnings/readme.md|docs/learnings/index.md) kind=index ;;
      *) continue ;;
    esac
    if ! [[ "$add" =~ ^[0-9]+$ && "$del" =~ ^[0-9]+$ ]]; then
      echo "FAIL $path: git cannot count its lines (binary?): keep it plain text"; bad=1; continue
    fi
    if [ "$kind" = index ] && [ "$add" -gt "$del" ]; then
      echo "FAIL $path: +$((add - del)) lines on a hand-made index (a merge-conflict hotspot): the table is printed by scripts/docs-index.sh, never committed"; bad=1
    elif [ "$kind" = guide ] && git -c core.fsmonitor= diff -a --no-ext-diff --no-textconv -U0 "$base" HEAD -- "$path" | grep -qE "^\+$DATED"; then
      echo "FAIL $path: a dated log entry added to the testing guide: a test note is its own file, docs/testing/<slug>.md"; bad=1
    fi
  done < <(git -c core.fsmonitor= -c core.quotePath=false diff -z -a --no-ext-diff --no-textconv --numstat --no-renames "$base" HEAD --)
fi
if [ "$bad" = 0 ]; then echo "hotspot-check: no shared log, no hotspot grows${how:+ (base: $how)}"; else echo "hotspot-check: ${how:+compared with base: $how}"; fi
exit "$bad"
