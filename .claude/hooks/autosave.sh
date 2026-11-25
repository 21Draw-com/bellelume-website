#!/bin/bash
# builder-kit 1.0.3: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Stop hook: safety net for uncommitted work at the end of a turn, on a work branch only. It never commits to a branch
# and never touches the default branch: it stores a snapshot as refs/autosave/<branch> and pushes that ref, so nothing
# is lost and branch history stays clean. Replaces the old autocommit (add -A on main + push).
# What goes in: ONLY files git already tracks (changed or deleted) and files you staged (`git add`). An untracked file
# is never saved, so a scratch export or a data dump does not reach GitHub: `git add` it to have it kept.
# Key and credential files (*.pem, *.p8, *.p12, *.pfx, *.key, *.keystore, *.jks, id_rsa*, id_ed25519*, .env*, .npmrc,
# .netrc, credentials*, *secret*, *.env, .pgpass, *.ppk, id_ecdsa*, .git-credentials, anything under .ssh/ or a
# *secret* folder; any letter case) never go into the snapshot, even staged: they keep HEAD's version.
# A snapshot whose new lines look like a secret (known token formats, key=value with a secret-like name, a URL with
# user:password@, an Authorization: Bearer header, a bare long key alone on a line or as name=/name: <key>), or that adds or
# changes a binary file, stays local (not pushed) and says so on stderr.
# What leaves the Mac (1.0.3): the snapshot's parent is the BASE, what the remote already has: origin/<branch> (the
# remote-tracking ref), or for a branch never pushed its merge-base with origin/<default>. So one commit leaves, never a
# local commit not yet pushed, and the scan covers everything new against the base: unpushed commits plus uncommitted
# work. Key files keep the base's version. No base (no origin ref), or anything else not on the remote reachable from the
# snapshot, keeps it local. Pushing your branch is yours to do (`git push`), not the hook's.
# Stale refs: scripts/job-session.sh close deletes refs/autosave/<branch> (here and on origin) once the branch is gone.
# Inspect: git diff HEAD refs/autosave/<branch>   Restore a file: git checkout refs/autosave/<branch> -- <file>
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
top="$(git rev-parse --show-toplevel 2>/dev/null)" && cd "$top" || exit 0
branch="$(git branch --show-current)"
[ -n "$branch" ] || exit 0
default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
case "$branch" in main|master|"${default:-main}") exit 0 ;; esac
[ -n "$(git status --porcelain --untracked-files=no)" ] || exit 0

keys=('**/*.pem' '**/*.p8' '**/*.p12' '**/*.pfx' '**/*.key' '**/*.keystore' '**/*.jks' '**/id_rsa*' '**/id_ed25519*'
  '**/.env*' '**/.npmrc' '**/.netrc' '**/credentials*' '**/*secret*'
  '**/*secret*/**' '**/.ssh/**' '**/*.env' '**/.pgpass' '**/*.ppk' '**/id_ecdsa*' '**/.git-credentials')  # 1.0.3: also inside folders
skip=(); only=(); for k in "${keys[@]}"; do skip+=(":(exclude,glob,icase)$k"); only+=(":(glob,icase)$k"); done
real="$(git rev-parse --git-path index)"
base="$(git rev-parse -q --verify "refs/remotes/origin/$branch^{commit}" 2>/dev/null)" ||
  base="$(git merge-base HEAD "refs/remotes/origin/${default:-main}" 2>/dev/null)" || base=""
local_only=0; [ -n "$base" ] || { base="$(git rev-parse HEAD)" || exit 0; local_only=1; }
tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT
export GIT_INDEX_FILE="$tmp"
# Start from the real index (tracked + staged), never from the working tree's untracked files.
if [ -f "$real" ]; then cp "$real" "$tmp" || exit 0; else git read-tree HEAD || exit 0; fi
git add -u -- . "${skip[@]}" || exit 0
git reset -q "$base" -- "${only[@]}" >/dev/null 2>&1 || exit 0   # a key file (staged or committed) keeps the base's version (or stays out)
tree="$(git write-tree)" || exit 0
q="[\"']?"
secret='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|sk_live_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}'
secret+="|(password|passwd|secret|token|api_?key)[A-Za-z_]*$q[[:space:]]*[:=][[:space:]]*$q[^[:space:]\"'\$<{]{8,}"
secret+='|[a-z][a-z0-9+.-]*://[^/:@[:space:]]+:[^/@[:space:]]+@'                                   # scheme://user:pass@host
secret+="|authorization$q[[:space:]]*[:=][[:space:]]*${q}bearer[[:space:]]+[A-Za-z0-9._~+/=-]{8,}"     # Authorization: Bearer
secret+="|^\+[[:space:]]*$q[A-Za-z0-9+/_=.-]{32,}$q[[:space:]]*,?[[:space:]]*\$"                        # a bare key on its own line
secret+="|^\+[[:space:]]*(export[[:space:]]+)?$q[A-Za-z_][A-Za-z0-9_.-]*$q[[:space:]]*[:=][[:space:]]*$q[A-Za-z0-9+/_=.-]{32,}"  # VAR=<key>, "name": "<key>", name: <key>
suspect=0
# No external diff or textconv driver (repo or global config) may empty the scan; a failed diff saves nothing (1.0.3).
diff="$(git diff --cached --no-ext-diff --no-textconv --text --no-color --no-prefix -U0 "$base")" || exit 0
bins="$(git diff --cached --no-ext-diff --no-textconv --numstat "$base")" || exit 0
# Added lines only: a file's header (from `diff --git` to its first `@@`) is skipped by position, never by pattern, so
# an added line that itself starts with `++` is still scanned (1.0.3).
awk '/^diff --git /{h=1} h&&/^@@/{h=0; next} !h&&/^\+/' <<<"$diff" | grep -qiE -- "$secret" && suspect=1
grep -qE $'^-\t-\t' <<<"$bins" && suspect=1
unset GIT_INDEX_FILE
[ "$tree" = "$(git rev-parse "$base^{tree}")" ] && exit 0
snap="$(git commit-tree "$tree" -p "$base" -m "auto-save $branch $(date '+%Y-%m-%d %H:%M')")" || exit 0
git update-ref "refs/autosave/$branch" "$snap" || exit 0
# Belt and braces: the snapshot must be the only commit the remote lacks (else unscanned history would leave).
new="$(git rev-list "$snap" --not --remotes=origin 2>/dev/null)" || local_only=1
[ "$new" = "$snap" ] || local_only=1
if [ "$local_only" = 1 ]; then
  echo "autosave: refs/autosave/$branch kept LOCAL: no remote base (origin/$branch or origin/${default:-main}) under it, so it would carry history the remote lacks." >&2
elif [ "$suspect" = 1 ]; then
  echo "autosave: refs/autosave/$branch kept LOCAL: a new line looks like a secret, or a binary file changed. Check it; never commit a secret." >&2
elif git remote get-url origin >/dev/null 2>&1; then
  GIT_TERMINAL_PROMPT=0 git push -q origin "+refs/autosave/$branch:refs/autosave/$branch" >/dev/null 2>&1 || true
fi
exit 0
