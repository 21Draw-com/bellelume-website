#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# The builder's system-prompt text in a shared repository (kit 1.4.0, infra-control#367 item 14). There the root CLAUDE.md
# belongs to the running service agent, and Claude Code loads a nested CLAUDE.md only when files in its folder are read,
# so the builder session is started with this text appended: `claude --append-system-prompt-file <file>`.
#   scripts/builder-prompt.sh [repo dir] > <file>     prints .claude/builder/CLAUDE.md with its import line
#                                                     `@../builder-rules.md` replaced by .claude/builder-rules.md itself
# Refuses (exit 1, nothing printed) unless .github/kit.conf says shared-repo=yes and both files are regular files (no
# symlink) and the import line is there. Used by job-session.sh (its own sibling copy) and by infra's starter, which runs
# the templates' own copy of this script, never the repository's.
set -u
root="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || { echo "builder-prompt: not in a git repository" >&2; exit 1; }
b="$root/.claude/builder/CLAUDE.md"; r="$root/.claude/builder-rules.md"
grep -qx 'shared-repo=yes' "$root/.github/kit.conf" 2>/dev/null || { echo "builder-prompt: .github/kit.conf has no shared-repo=yes" >&2; exit 1; }
for f in "$b" "$r"; do [ -f "$f" ] && [ ! -L "$f" ] || { echo "builder-prompt: $f missing or not a regular file" >&2; exit 1; }; done
grep -qE '^@\.\./builder-rules\.md[[:space:]]*$' "$b" || { echo "builder-prompt: $b has no line '@../builder-rules.md'" >&2; exit 1; }
while IFS= read -r l || [ -n "$l" ]; do
  if [[ "$l" =~ ^@\.\./builder-rules\.md[[:space:]]*$ ]]; then cat "$r"; else printf '%s\n' "$l"; fi
done < "$b"
