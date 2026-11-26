#!/bin/bash
# Tests for scripts/job-session.sh (#169): hanging gh, unreadable issue, odd branch name, leading zeros; kit 1.0.2: an
# issue's author and last editor must be the builder's own App (1.0.8: no code owner), and close deletes stale autosave refs; kit
# 1.0.3: owners from GitHub's default branch (not the working copy), the checked issue saved as the job's brief, and a
# never-pushed branch deleted locally keeps its snapshot.
# Fake gh/tmux in $HOME/bin (the script puts $HOME/bin first on PATH); origin is a local bare repo; no network.
# Run: bash templates/builder-kit/tests/job-session.test.sh
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"; script="$here/scripts/job-session.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME/bin" "$tmp/fakerepo"
printf '#!/bin/bash\ncase "$GH_MODE" in hang) exec sleep 31337;; fail) exit 1;; *) case "$*" in *graphql*) [ -n "$GH_WRITERS" ] && printf "%%s\\n[prio-1] Test job\\nProfile: opus high\\n" "$GH_WRITERS";; esac;; esac\n' >"$HOME/bin/gh"
printf '#!/bin/bash\nexit 1\n' >"$HOME/bin/tmux"; chmod +x "$HOME/bin/gh" "$HOME/bin/tmux"
origin="$tmp/github.com/o/fakerepo.git"; mkdir -p "$origin" && git init -q --bare "$origin"
cd "$tmp/fakerepo" && git init -q -b main . && git config user.name 'builder-x[bot]' && git config user.email b@b \
  && mkdir .github && printf '/scripts/   @owner1 @owner2\n/docs/  @someone-else\n' > .github/CODEOWNERS && git add .github && git commit -q -m i \
  && git remote add origin "$origin" && git push -q origin main && git fetch -q origin \
  && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
export GH_WRITERS='builder-x[bot] -'
run() { out="$(env GH_MODE="$1" JOB_GH_TIMEOUT="${JOB_GH_TIMEOUT:-1}" "$script" "${@:2}" 2>&1)"; rc=$?; }

run ok start 5 --dry-run;   [ $rc = 0 ] && grep -q 'opus --effort high' <<<"$out" && ok "readable issue: dry run uses the profile" || bad "readable dry run: $rc $out"
run fail start 5 --dry-run; [ $rc = 0 ] && grep -q "issue 5" <<<"$out" && grep -q 'sonnet --effort medium' <<<"$out" && ok "unreadable issue: dry run falls back" || bad "fallback: $rc $out"
run fail start 5;           [ $rc = 2 ] && grep -q 'cannot read title, body' <<<"$out" && ok "unreadable issue: real start stops" || bad "real start did not stop: $rc $out"
s=$SECONDS; run hang start 5; el=$((SECONDS-s))
[ $rc = 2 ] && [ $el -lt 15 ] && ok "hanging gh: real start stops in ${el}s" || bad "hanging gh: rc=$rc ${el}s $out"
sleep 1; ! pgrep -f 'sleep 31337' >/dev/null && ok "hanging gh: no orphan sleep or gh left" || { bad "orphan sleep left"; pkill -f 'sleep 31337'; }
run ok start 007 --dry-run; [ $rc = 2 ] && ok "leading zero refused" || bad "leading zero accepted: $rc"
run ok start 5 --dryrun;    [ $rc = 2 ] && ok "unknown argument refused" || bad "unknown argument: $rc"
git -C "$tmp/fakerepo" symbolic-ref refs/remotes/origin/HEAD 'refs/remotes/origin/x;touch${IFS}pwned'
run ok start 5 --dry-run;   [ $rc = 2 ] && grep -q 'odd default branch' <<<"$out" && [ ! -e "$tmp/fakerepo/pwned" ] && ok "odd branch name refused" || bad "odd branch: $rc $out"
git -C "$tmp/fakerepo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# 1.0.2 finding 4: who wrote the issue
run ok start 5 --dry-run;   grep -q 'issue writers: builder-x\[bot\] -' <<<"$out" && ok "the builder's own issue passes" || bad "own issue: $rc $out"
GH_WRITERS='owner2 builder-x[bot]' run ok start 5; [ $rc = 2 ] && grep -q 'author owner2' <<<"$out" && ok "1.0.8: a CODEOWNERS owner (shared login) as author is refused" || bad "owner author: $rc $out"
GH_WRITERS='stranger -' run ok start 5;  [ $rc = 2 ] && grep -q 'author stranger' <<<"$out" && ok "an outside author is refused" || bad "outside author: $rc $out"
GH_WRITERS='builder-x[bot] stranger' run ok start 5; [ $rc = 2 ] && grep -q 'last editor stranger' <<<"$out" && ok "an outside last editor is refused" || bad "outside editor: $rc $out"
GH_WRITERS='other-builder[bot] -' run ok start 5; [ $rc = 2 ] && grep -q 'author other-builder\[bot\]' <<<"$out" && ok "another App is refused" || bad "other app: $rc $out"
GH_WRITERS='builder-x[bot] owner1' run ok start 5; [ $rc = 2 ] && grep -q 'last editor owner1' <<<"$out" && ok "1.0.8: an owner who edited the builder's issue is refused" || bad "owner editor: $rc $out"
GH_WRITERS='' run ok start 5; [ $rc = 2 ] && grep -q 'cannot read title, body, author' <<<"$out" && ok "unreadable writers: real start stops" || bad "unreadable writers: $rc $out"
# 1.0.3/1.0.8: CODEOWNERS (also a local edit) grants no trust at all
cd "$tmp/fakerepo" || exit 1; git switch -q -c evil && printf '/scripts/ @stranger\n' > .github/CODEOWNERS && git commit -qam evil
GH_WRITERS='stranger -' run ok start 5 --dry-run; [ $rc = 2 ] && grep -q 'author stranger' <<<"$out" && ok "dry run: a local CODEOWNERS edit trusts nobody" || bad "local codeowners trusted (dry): $rc $out"
GH_WRITERS='stranger -' run ok start 5; [ $rc = 2 ] && grep -q 'author stranger' <<<"$out" && ok "real start: owners read from origin's default branch" || bad "local codeowners trusted: $rc $out"
git switch -q main; git branch -q -D evil
# 1.0.3 (warehouse finding 3): the checked issue is the job's brief, outside the worktree; close removes it
brief="$tmp/fakerepo-wt/5.issue.md"; run ok start 5
! grep -q 'Test job' "$brief" 2>/dev/null && grep -q 'Profile: opus high' "$brief" && [ -z "$(git status --porcelain)" ] \
  && ok "a real start saves the checked body (not the title) as the brief" || bad "no brief: $rc $out"
run ok close 5; [ ! -e "$brief" ] && ok "close removes the brief" || bad "brief left: $out"

# 1.0.2 finding 5: close deletes refs/autosave/<b> once <b> is gone; keeps it for a live or never-pushed branch
cd "$tmp/fakerepo" || exit 1; snap="$(git rev-parse HEAD)"
for b in gone merged wip live lost; do git update-ref "refs/autosave/$b" "$snap"; done
git update-ref refs/remotes/origin/gone "$snap"                                                # was pushed, gone on GitHub, no local branch
git branch -q merged && git push -q -u origin merged && git push -q origin --delete merged     # merged, deleted on GitHub
git branch -q wip                                                                             # local, never pushed
git push -q origin HEAD:refs/heads/live; git push -q origin refs/autosave/gone refs/autosave/merged refs/autosave/live refs/autosave/lost
# lost: never pushed, local branch deleted; its snapshot may be the only copy (warehouse finding 5, 1.0.3)
run ok close 9
has() { git -C "$tmp/fakerepo" show-ref -q --verify "refs/autosave/$1"; }; rhas() { git --git-dir="$origin" show-ref -q --verify "refs/autosave/$1"; }
! has gone && ! rhas gone && ! has merged && ! rhas merged && ok "close deletes autosave refs of gone branches, here and on origin" || bad "stale refs left: $out"
has wip && has live && rhas live && ok "close keeps the refs of a never-pushed and a live branch" || bad "live refs deleted: $out"
has lost && rhas lost && grep -q 'kept refs/autosave/lost' <<<"$out" && ok "close keeps the snapshot of a never-pushed, locally deleted branch" || bad "lost snapshot deleted: $out"
exit $fail
