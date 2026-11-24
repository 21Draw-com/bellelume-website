#!/bin/bash
# builder-kit 1.0.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Stop hook: safety net for uncommitted work at the end of a turn, on a work branch only. It never commits to a branch
# and never touches the default branch: it stores a snapshot of the working tree as refs/autosave/<branch> and pushes
# that ref, so nothing is lost and branch history stays clean. Replaces the old autocommit (add -A on main + push).
# Key and credential files (*.pem, *.p8, *.p12, *.pfx, *.key, *.keystore, *.jks, id_rsa*, id_ed25519*, .env*, .npmrc,
# .netrc, credentials*, *secret*) never go into the snapshot. A snapshot whose new lines look like a secret, or that adds or changes a binary file,
# stays local (not pushed) and says so on stderr.
# Inspect: git diff HEAD refs/autosave/<branch>   Restore a file: git checkout refs/autosave/<branch> -- <file>
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
branch="$(git branch --show-current)"
[ -n "$branch" ] || exit 0
default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
case "$branch" in main|master|"${default:-main}") exit 0 ;; esac
[ -n "$(git status --porcelain)" ] || exit 0

tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT
export GIT_INDEX_FILE="$tmp"
git read-tree HEAD || exit 0
git add -A -- . ':(exclude,glob)**/*.pem' ':(exclude,glob)**/*.p8' ':(exclude,glob)**/*.p12' ':(exclude,glob)**/*.pfx' \
  ':(exclude,glob)**/*.key' ':(exclude,glob)**/*.keystore' ':(exclude,glob)**/*.jks' ':(exclude,glob)**/id_rsa*' \
  ':(exclude,glob)**/id_ed25519*' ':(exclude,glob)**/.env*' ':(exclude,glob)**/.npmrc' ':(exclude,glob)**/.netrc' \
  ':(exclude,glob)**/credentials*' ':(exclude,glob)**/*secret*' || exit 0
tree="$(git write-tree)" || exit 0
secret='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|sk_live_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}|(password|passwd|secret|token|api_?key)[A-Za-z_]*["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?[^[:space:]"'\''$<{]{8,}'
suspect=0
diff="$(git diff --cached --no-color -U0 HEAD)"
grep -E '^\+' <<<"$diff" | grep -qiE -- "$secret" && suspect=1
grep -qE '^Binary files ' <<<"$diff" && suspect=1
unset GIT_INDEX_FILE
[ "$tree" = "$(git rev-parse 'HEAD^{tree}')" ] && exit 0
snap="$(git commit-tree "$tree" -p HEAD -m "auto-save $branch $(date '+%Y-%m-%d %H:%M')")" || exit 0
git update-ref "refs/autosave/$branch" "$snap" || exit 0
if [ "$suspect" = 1 ]; then
  echo "autosave: refs/autosave/$branch kept LOCAL: a new line looks like a secret, or a binary file changed. Check it; never commit a secret." >&2
elif git remote get-url origin >/dev/null 2>&1; then
  GIT_TERMINAL_PROMPT=0 git push -q origin "+refs/autosave/$branch:refs/autosave/$branch" >/dev/null 2>&1 || true
fi
exit 0
