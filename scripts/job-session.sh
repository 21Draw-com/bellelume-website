#!/bin/bash
# Visible job sessions for a builder (#147, pattern of #144). Run by the MAIN builder session in its own account; no root.
# One independent issue = one tmux session + Claude Remote session "<repo>-<N> <short issue title>" in its own git worktree,
# closed after its PR. Reference copy; the agent templates carry the same script.
#   scripts/job-session.sh start <N> [--dry-run]   worktree ../<repo>-wt/<N> on fresh main, session <repo>-<N>
#   scripts/job-session.sh close <N>               end the session, remove the worktree only when clean (no force)
#   scripts/job-session.sh list                    running job sessions of this repo
# Checks (same as infra-helper builder): clean main clone, fast-forward to GitHub's main, one session per N, at most 3.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
T=tmux; MAX=3
die() { echo "job-session: $*" >&2; exit 2; }
usage() { echo "usage: job-session.sh start <N> [--dry-run] | close <N> | list" >&2; exit 2; }
cmd="${1:-}"; [ -n "$cmd" ] || usage; shift || true
common="$(git rev-parse --git-common-dir 2>/dev/null)" || die "not in a git repository"
main="$(cd "$common/.." && pwd)"                       # the main clone, also when called from a job worktree
url="$(git -C "$main" remote get-url origin | sed -E 's#^(https://)[^@/]*@#\1#')"; slug="$(sed -E 's#.*github.com[:/]##; s#\.git$##' <<<"$url")"
repo="$(basename "$main")"; [ "${repo%-wt}" = "$repo" ] || die "run from the main clone"
base="$(dirname "$main")/$repo-wt"
running() { "$T" list-sessions -F '#{session_name}' 2>/dev/null | grep -E "^$repo-[0-9]+$" || true; }
num() { [[ "${1:-}" =~ ^[0-9]{1,6}$ ]] || usage; }
case "$cmd" in
list) running ;;
start)
  num "${1:-}"; n="$1"; dry="${2:-}"; sess="$repo-$n"; wt="$base/$n"
  [ -z "$dry" ] || [ "$dry" = --dry-run ] || usage
  ! "$T" has-session -t "=$sess" 2>/dev/null || die "$sess is running already"
  [ "$(running | grep -c .)" -lt "$MAX" ] || die "$MAX job sessions run already: close one first"
  [ ! -e "$wt" ] || die "$wt exists: close job $n first"
  [ -z "$(git -C "$main" status --porcelain)" ] || die "$main has uncommitted changes"
  title="$(gh issue view "$n" -R "$slug" --json title --jq .title | sed -E 's/^(\[[^]]*\] *)+//' | tr -cd 'A-Za-z0-9 .,-' | cut -c1-40)"
  name="$sess $title"
  prompt="Your first line: the link https://github.com/$slug/issues/$n . Build GitHub issue $slug#$n exactly as written (read it with gh), on a branch, open ONE pull request and stop. Never push to main, never merge, touch only the files the issue names. End by commenting the PR link on issue #$n so the main builder sees it. Last step: SendMessage to infra-control: PR link ready for review (or: stopped, with the reason)."
  if [ "$dry" = --dry-run ]; then echo "would: ff $main to origin/main; git worktree add --detach $wt; tmux new-session -d -s $sess -c $wt claude --name '$name' --remote-control '$name'"; exit 0; fi
  git -C "$main" switch -q main && git -C "$main" fetch -q origin main && git -C "$main" merge -q --ff-only FETCH_HEAD || die "cannot fast-forward $main"
  [ "$(git -C "$main" rev-parse HEAD)" = "$(git -C "$main" ls-remote origin refs/heads/main | cut -f1)" ] || die "$main is not GitHub's main"
  git -C "$main" worktree add -q --detach "$wt" HEAD
  "$T" new-session -d -s "$sess" -c "$wt" /bin/zsh -lic "claude --name '$name' --remote-control '$name' --permission-mode auto \"$prompt\""
  echo "started $sess in $wt: visible in Claude Remote as '$name'" ;;
close)
  num "${1:-}"; n="$1"; sess="$repo-$n"; wt="$base/$n"
  "$T" kill-session -t "=$sess" 2>/dev/null && echo "closed $sess" || echo "no $sess session"
  [ ! -d "$wt" ] || { git -C "$main" worktree remove "$wt" 2>/dev/null && echo "removed worktree $wt" || echo "worktree $wt kept (not clean): look first"; } ;;
*) usage ;;
esac
