#!/bin/bash
# Tests for scripts/job-session.sh (#169): hanging gh, unreadable issue, odd branch name, leading zeros.
# Fake gh/tmux in $HOME/bin (the script puts $HOME/bin first on PATH); no network, no real session.
# Run: bash templates/builder-kit/tests/job-session.test.sh
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"; script="$here/scripts/job-session.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME/bin" "$tmp/fakerepo"
printf '#!/bin/bash\ncase "$GH_MODE" in hang) exec sleep 31337;; fail) exit 1;; *) case "$*" in *title*) echo "[prio-1] Test job";; *) printf "Profile: opus high\\n";; esac;; esac\n' >"$HOME/bin/gh"
printf '#!/bin/bash\nexit 1\n' >"$HOME/bin/tmux"; chmod +x "$HOME/bin/gh" "$HOME/bin/tmux"
cd "$tmp/fakerepo" && git init -q -b main . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i \
  && git remote add origin https://github.com/o/fakerepo.git && git update-ref refs/remotes/origin/main HEAD \
  && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
run() { out="$(env GH_MODE="$1" JOB_GH_TIMEOUT="${JOB_GH_TIMEOUT:-1}" "$script" "${@:2}" 2>&1)"; rc=$?; }

run ok start 5 --dry-run;   [ $rc = 0 ] && grep -q 'opus --effort high' <<<"$out" && ok "readable issue: dry run uses the profile" || bad "readable dry run: $rc $out"
run fail start 5 --dry-run; [ $rc = 0 ] && grep -q "issue 5" <<<"$out" && grep -q 'sonnet --effort medium' <<<"$out" && ok "unreadable issue: dry run falls back" || bad "fallback: $rc $out"
run fail start 5;           [ $rc = 2 ] && grep -q 'cannot read title and body' <<<"$out" && ok "unreadable issue: real start stops" || bad "real start did not stop: $rc $out"
s=$SECONDS; run hang start 5; el=$((SECONDS-s))
[ $rc = 2 ] && [ $el -lt 15 ] && ok "hanging gh: real start stops in ${el}s" || bad "hanging gh: rc=$rc ${el}s $out"
sleep 1; ! pgrep -f 'sleep 31337' >/dev/null && ok "hanging gh: no orphan sleep or gh left" || { bad "orphan sleep left"; pkill -f 'sleep 31337'; }
run ok start 007 --dry-run; [ $rc = 2 ] && ok "leading zero refused" || bad "leading zero accepted: $rc"
run ok start 5 --dryrun;    [ $rc = 2 ] && ok "unknown argument refused" || bad "unknown argument: $rc"
git -C "$tmp/fakerepo" symbolic-ref refs/remotes/origin/HEAD 'refs/remotes/origin/x;touch${IFS}pwned'
run ok start 5 --dry-run;   [ $rc = 2 ] && grep -q 'odd default branch' <<<"$out" && [ ! -e "$tmp/fakerepo/pwned" ] && ok "odd branch name refused" || bad "odd branch: $rc $out"
exit $fail
