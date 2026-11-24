#!/bin/bash
# builder-kit 1.0.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Visible job sessions for a builder (#147, pattern of #144). Run by the MAIN builder session in its own account; no root.
# One independent issue = one tmux session + Claude Remote session "<repo>-<N> <short issue title>" in its own git worktree,
# closed after its PR. A kit file infra ships; the same file in every builder repo.
#   scripts/job-session.sh start <N> [--dry-run]   worktree ../<repo>-wt/<N> on fresh default branch, session <repo>-<N>
#   scripts/job-session.sh close <N> [--dry-run]   end the session, remove the worktree only when clean (no force)
#   scripts/job-session.sh list                    running job sessions of this repo
# Every subcommand checks its exact argument count; --dry-run (start and close) only prints and never acts; anything else exits 2 (#166).
# Model and effort come from the issue's line `Profile: <model> <effort>` (model sonnet|opus|fable|haiku, effort low|medium|high|xhigh|max;
# the planner sets it, see skill planning). No such line: sonnet medium. The dry run shows the choice.
# Every gh call is bounded (JOB_GH_TIMEOUT, default 20 s; macOS has no timeout), and so are fetch/ls-remote of a real start (JOB_GIT_TIMEOUT, 60 s).
# Dry run only: no title -> "issue N", no profile -> sonnet medium. A REAL start stops when title or body cannot be read (#169). No default branch -> stop.
# Branch name and repo slug are checked against a strict pattern before they go into any command string; N has no leading zeros (#169).
# The default branch is read from the repo (origin/HEAD, else gh), never assumed to be main (#155).
# Checks (same as infra-helper builder): clean main clone, fast-forward to GitHub's default branch, one session per N, at most 3.
set -euo pipefail
export PATH="$HOME/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
T=tmux; MAX=3
die() { echo "job-session: $*" >&2; exit 2; }
usage() { echo "usage: job-session.sh start <N> [--dry-run] | close <N> [--dry-run] | list" >&2; exit 2; }
cmd="${1:-}"; [ -n "$cmd" ] || usage; shift || true
common="$(git rev-parse --git-common-dir 2>/dev/null)" || die "not in a git repository"
main="$(cd "$common/.." && pwd)"                       # the main clone, also when called from a job worktree
url="$(git -C "$main" remote get-url origin | sed -E 's#^(https://)[^@/]*@#\1#')"; slug="$(sed -E 's#.*github.com[:/]##; s#\.git$##' <<<"$url")"
repo="$(basename "$main")"; [ "${repo%-wt}" = "$repo" ] || die "run from the main clone"
base="$(dirname "$main")/$repo-wt"
with_timeout() { local s="$1" p w rc=0; shift; "$@" & p=$!; { sleep "$s"; pkill -P "$p" || true; kill "$p" || true; } >/dev/null 2>&1 & w=$!
  wait "$p" 2>/dev/null || rc=$?; pkill -P "$w" >/dev/null 2>&1 || true; kill "$w" >/dev/null 2>&1 || true; wait "$w" 2>/dev/null || true; return "$rc"; }
gh_t() { with_timeout "${JOB_GH_TIMEOUT:-20}" gh "$@"; }
running() { "$T" list-sessions -F '#{session_name}' 2>/dev/null | grep -E "^$repo-[0-9]+$" || true; }
profile() { local l; l="$(printf '%s\n' "$1" | grep -iEm1 '^[[:space:]>*-]*profile:[[:space:]]*(sonnet|opus|fable|haiku)[[:space:]]+(low|medium|high|xhigh|max)[[:space:]]*$' | tr 'A-Z' 'a-z' | sed -E 's/^[^a-z]*profile:[[:space:]]*//')" || true
  echo "${l:-sonnet medium}"; }
defbranch() { local b; b="$(git -C "$main" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')" || true
  [ -n "$b" ] || b="$(gh_t repo view "$slug" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)" || true
  [ -n "$b" ] || die "cannot determine the default branch of $slug"
  [[ "$b" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*$ && "$b" != *..* && "$b" != *// && "$b" != *.lock ]] || die "odd default branch name"; echo "$b"; }
argc() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ] || usage; }   # argc <have> <min> <max>
num() { [[ "${1:-}" =~ ^[1-9][0-9]{0,5}$ ]] || usage; }
[[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "odd repo slug"
case "$cmd" in
list) argc $# 0 0; running ;;
start)
  argc $# 1 2; num "${1:-}"; n="$1"; dry="${2:-}"; sess="$repo-$n"; wt="$base/$n"
  [ -z "$dry" ] || [ "$dry" = --dry-run ] || usage
  ! "$T" has-session -t "=$sess" 2>/dev/null || die "$sess is running already"
  [ "$(running | grep -c .)" -lt "$MAX" ] || die "$MAX job sessions run already: close one first"
  [ ! -e "$wt" ] || die "$wt exists: close job $n first"
  [ -z "$(git -C "$main" status --porcelain)" ] || die "$main has uncommitted changes"
  br="$(defbranch)"
  # one read of the issue; a real start stops when it cannot be read, the fallbacks are for --dry-run only (#169)
  rawtitle="$(gh_t issue view "$n" -R "$slug" --json title --jq .title 2>/dev/null)" || rawtitle=""
  body="$(gh_t issue view "$n" -R "$slug" --json body --jq .body 2>/dev/null)" || body=""
  if [ -z "$dry" ]; then [ -n "$rawtitle" ] && [ -n "$body" ] || die "cannot read title and body of $slug#$n: not starting"; fi
  set -- $(profile "$body"); model="$1"; effort="$2"
  title="$(printf '%s' "$rawtitle" | sed -E 's/^(\[[^]]*\] *)+//' | tr -cd 'A-Za-z0-9 .,-' | cut -c1-40)"
  [ -n "$title" ] || { [ -n "$dry" ] && title="issue $n" || die "issue $n has no usable title: not starting"; }
  name="$sess $title"
  prompt="Your first line: the link https://github.com/$slug/issues/$n . Build GitHub issue $slug#$n exactly as written (read it with gh), on a branch, open ONE pull request and stop. Never push to $br, never merge, touch only the files the issue names. End by commenting the PR link on issue #$n so the main builder sees it. Last step: SendMessage to infra-control: PR link ready for review (or: stopped, with the reason)."
  if [ "$dry" = --dry-run ]; then echo "would: ff $main to origin/$br; git worktree add --detach $wt; tmux new-session -d -s $sess -c $wt claude --model $model --effort $effort --name '$name' --remote-control '$name'"; exit 0; fi
  gt() { with_timeout "${JOB_GIT_TIMEOUT:-60}" git "$@"; }
  git -C "$main" switch -q "$br" && gt -C "$main" fetch -q origin "$br" && git -C "$main" merge -q --ff-only FETCH_HEAD || die "cannot fast-forward $main"
  remote="$(gt -C "$main" ls-remote origin "refs/heads/$br")" || die "cannot reach origin"
  [ "$(git -C "$main" rev-parse HEAD)" = "$(printf '%s' "$remote" | cut -f1)" ] || die "$main is not GitHub's $br"
  git -C "$main" worktree add -q --detach "$wt" HEAD
  "$T" new-session -d -s "$sess" -c "$wt" /bin/zsh -lic "claude --model $model --effort $effort --name '$name' --remote-control '$name' --permission-mode auto \"$prompt\""
  echo "started $sess in $wt ($model, $effort): visible in Claude Remote as '$name'" ;;
close)
  argc $# 1 2; num "${1:-}"; n="$1"; dry="${2:-}"; sess="$repo-$n"; wt="$base/$n"
  [ -z "$dry" ] || [ "$dry" = --dry-run ] || usage
  if [ "$dry" = --dry-run ]; then echo "would: tmux kill-session -t =$sess; git worktree remove $wt (only when clean, no force)"; exit 0; fi
  "$T" kill-session -t "=$sess" 2>/dev/null && echo "closed $sess" || echo "no $sess session"
  [ ! -d "$wt" ] || { git -C "$main" worktree remove "$wt" 2>/dev/null && echo "removed worktree $wt" || echo "worktree $wt kept (not clean): look first"; } ;;
*) usage ;;
esac
