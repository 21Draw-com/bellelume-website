#!/bin/bash
# builder-kit 1.0.9: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# A task from infra or the owner arrives as a channel brief; this turns it into the builder's OWN issue, the only kind
# `job-session.sh start` runs (the login renco-og is shared, so an issue it opens is never trusted).
#   scripts/brief-issue.sh <brief file name>     e.g. 2026-11-26-0900-infra-control-task-foo.md
# Steps: (1) `stat` proves the brief AND its folder /Users/Shared/infra-naar-$(id -un)/ are owned by rencosmeding
# (a symlink or a non-regular file is refused); (2) the issue is opened with gh, i.e. under this clone's own App, with
# the brief's title (first "# " line, else the file name) and body, the first body line being "From infra brief <name>";
# (3) the issue number is printed: it is the issue for `scripts/job-session.sh start <N>`. Nothing else is written.
# BRIEF_ROOT (default /Users/Shared) exists for the tests only.
set -euo pipefail
export PATH="$HOME/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
die() { echo "brief-issue: $*" >&2; exit 2; }
[ $# -eq 1 ] || die "usage: brief-issue.sh <brief file name>"
name="$1"; [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.md$ && "$name" != *..* ]] || die "odd brief name (a plain file name ending in .md, no path)"
acct="$(id -un)"; [[ "$acct" =~ ^[A-Za-z0-9_.-]+$ ]] || die "odd account name"
dir="${BRIEF_ROOT:-/Users/Shared}/infra-naar-$acct"; file="$dir/$name"
owner() { stat -f %Su "$1" 2>/dev/null; }
[ -d "$dir" ] && [ ! -L "$dir" ] || die "$dir is not a folder"
[ "$(owner "$dir")" = rencosmeding ] || die "$dir is not owned by rencosmeding: not opening an issue"
[ -f "$file" ] && [ ! -L "$file" ] || die "$file is not a regular file"
[ "$(owner "$file")" = rencosmeding ] || die "$file is not owned by rencosmeding: ignored"
common="$(git rev-parse --git-common-dir 2>/dev/null)" || die "not in a git repository"
main="$(cd "$common/.." && pwd)"
slug="$(git -C "$main" remote get-url origin | sed -E 's#^(https://)[^@/]*@#\1#; s#.*github.com[:/]##; s#\.git$##')"
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "odd repo slug"
title="$(sed -nE '1,/^[^#]/{s/^#[[:space:]]+//p;}' "$file" | head -n1 | tr -d '\r' | cut -c1-200)"; [ -n "$title" ] || title="${name%.md}"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
{ printf 'From infra brief %s\n\n' "$name"; cat "$file"; } > "$tmp"
url="$(gh issue create --repo "$slug" --title "$title" --body-file "$tmp")" || die "gh could not open the issue"
num="$(sed -nE 's#.*/issues/([1-9][0-9]*)$#\1#p' <<<"$url" | tail -n1)"; [ -n "$num" ] || die "no issue number in gh's answer"
echo "$num"
