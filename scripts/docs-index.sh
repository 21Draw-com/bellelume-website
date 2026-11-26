#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# One file per entry, the table generated (kit 1.4.0, infra-control#357/#367 item 4). Nothing here is committed: a committed
# index would be the next merge-conflict hotspot (scripts/hotspot-check.sh freezes the old shared files and any hand index).
#   scripts/docs-index.sh <decisions|testing|learnings>   print the index of docs/<kind>/ as a Markdown table
#   scripts/docs-index.sh next                            print the next free decision number (NNNN)
# File names: docs/decisions/NNNN-<slug>.md, docs/testing/<slug>.md, docs/learnings/YYYY-MM-DD-<slug>.md. Two parallel PRs
# may take the same NNNN: that is fine (no conflict); the file name is the reference, the table sorts by name.
# Columns: file (linked), title (the first heading, any level, else the name), date (the first YYYY-MM-DD in the name or the first
# five lines, else "-"). Read-only.
set -u
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "docs-index: not in a git repository" >&2; exit 2; }
kind="${1:-}"
case "$kind" in
  next)
    n="$(cd "$root" && ls docs/decisions 2>/dev/null | sed -nE 's/^([0-9]{4})-.*\.md$/\1/p' | sort | tail -n1)"
    printf '%04d\n' "$(( 10#${n:-0} + 1 ))"; exit 0 ;;
  decisions|testing|learnings) ;;
  *) echo "usage: docs-index.sh <decisions|testing|learnings|next>" >&2; exit 2 ;;
esac
dir="docs/$kind"
echo "| File | Title | Date |"
echo "|---|---|---|"
[ -d "$root/$dir" ] || exit 0
while IFS= read -r f; do
  case "$f" in *.md) ;; *) continue ;; esac
  low="$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')"; case "$low" in readme.md|index.md) continue ;; esac
  p="$root/$dir/$f"
  title="$(sed -nE 's/^#{1,6}[[:space:]]+//p' "$p" | head -n1 | tr -d '\r|' | cut -c1-120)"; [ -n "$title" ] || title="${f%.md}"
  date="$(printf '%s\n' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1)"
  [ -n "$date" ] || date="$(head -n5 "$p" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1)"
  echo "| [$f]($dir/$f) | $title | ${date:--} |"
done < <(cd "$root/$dir" && ls | LC_ALL=C sort)
