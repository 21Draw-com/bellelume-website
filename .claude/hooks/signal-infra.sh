#!/bin/bash
# builder-kit 1.3.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Stop hook "look now" (infra-control#315 S4): when this session changed GitHub since its last stop, send infra's
# inbox ONE fixed line, `changed <owner>/<repo>`, and nothing else. No free text ever. Infra's handler (code, before any
# model) accepts only that exact form for a repo it watches and then reads GitHub itself; a lost or forged signal costs
# nothing (infra's `ledger.sh delta` catches up at the next start or prompt).
# "Changed" is decided by code: a fingerprint of the repo's branch and tag refs on origin (never refs/autosave, which this
# kit pushes at every stop) plus the newest issue/PR update time, compared with the one stored at the last successful
# signal. The first stop of a repo has nothing to compare with and signals once.
# Config, per macOS account, in $INFRA_SIGNAL_DIR (default ~/.infra-signal; the directory and both files are the
# account's own, nobody else may read them): `url` = the infra-inbox endpoint, a loopback http URL; `token` = this
# account's own inbox token, read from the file and sent in a header (never in a URL, argv or settings). 1.2.1: curl runs with
# `-q` (no ~/.curlrc), `--noproxy '*'` (no proxy ever sees the Bearer token) and `--proto =http` (no other protocol or redirect). No config = this
# hook does nothing (a repo whose account has no infra-inbox, e.g. Habloop before its own token exists, is simply silent).
# Fail-soft and bounded: every step has a timeout (about 20 s in all), every failure exits 0, it never blocks a stop and
# never prints. The state moves only after infra accepted the signal, so a failed send is tried again at the next stop.
# Polling it is not: it runs once per stop, an event.
cat >/dev/null 2>&1
exit_ok() { exit 0; }
cfg="${INFRA_SIGNAL_DIR:-$HOME/.infra-signal}"
[ -f "$cfg/url" ] && [ -f "$cfg/token" ] || exit_ok
# private to this account: owned by me, no group/other access on the directory or the files
# fails closed (1.2.1): when find itself errors (unreadable directory, a missing tool) the privacy check is NOT passed
own="$(find "$cfg" "$cfg/url" "$cfg/token" -maxdepth 0 ! -user "$(id -un)" 2>/dev/null)" || exit_ok; [ -z "$own" ] || exit_ok
perm="$(find "$cfg" "$cfg/url" "$cfg/token" -maxdepth 0 \( -perm -g=r -o -perm -g=w -o -perm -g=x -o -perm -o=r -o -perm -o=w -o -perm -o=x \) 2>/dev/null)" || exit_ok; [ -z "$perm" ] || exit_ok
url="$(head -c 300 "$cfg/url" | head -1)"; tok="$(head -c 300 "$cfg/token" | head -1)"
[[ "$url" =~ ^http://(127\.0\.0\.1|localhost):[0-9]{2,5}(/[A-Za-z0-9._/-]*)?$ ]] || exit_ok
[[ "$tok" =~ ^[A-Za-z0-9._~+/=-]{16,200}$ ]] || exit_ok

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit_ok
top="$(git rev-parse --show-toplevel 2>/dev/null)" && cd "$top" || exit_ok
remote="$(git config --get remote.origin.url 2>/dev/null)" || exit_ok
repo="$(sed -nE 's#^(https://([^/@]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\3#p' <<<"$remote")"
repo="${repo%/}"; repo="${repo%.git}"
[[ "$repo" =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] || exit_ok

with_timeout() { local s="$1" p w rc=0; shift; "$@" & p=$!; { sleep "$s"; pkill -P "$p" || true; kill "$p" || true; } >/dev/null 2>&1 & w=$!
  wait "$p" 2>/dev/null || rc=$?; pkill -P "$w" >/dev/null 2>&1 || true; kill "$w" >/dev/null 2>&1 || true; wait "$w" 2>/dev/null || true; return "$rc"; }
# Listener owner (1.2.1, infra verdict on templates#197): a process that is listening on the port must be the admin's. A listener owned
# by any other uid that lsof can see (the builder's own account, say) means the port was taken over: no send, the token stays home.
# Limit: lsof run as a normal user does not list another account's sockets, so a listener of a third account is invisible here;
# that case is closed on infra's side (its inbox holds the port and checks the token). Unresolvable admin user = refuse.
port="${url#http://*:}"; port="${port%%/*}"
admin_uid="$(id -u "${INFRA_SIGNAL_ADMIN_USER:-rencosmeding}" 2>/dev/null)" || exit_ok
lis="$(with_timeout 4 lsof -nP -iTCP:"$port" -sTCP:LISTEN -Fu 2>/dev/null | sed -n 's/^u//p' | sort -u)"
[ -z "$lis" ] || [ "$lis" = "$admin_uid" ] || exit_ok

if command -v sha256sum >/dev/null 2>&1; then hash() { sha256sum | cut -d' ' -f1; }; else hash() { shasum -a 256 | cut -d' ' -f1; }; fi

refs="$(GIT_TERMINAL_PROMPT=0 with_timeout 8 git ls-remote --heads --tags origin 2>/dev/null)" || exit_ok
newest="$(with_timeout 8 gh api "repos/$repo/issues?state=all&sort=updated&direction=desc&per_page=1" --jq '.[0] | "\(.number) \(.updated_at)"' 2>/dev/null)" || exit_ok
fp="$(printf '%s\n%s\n' "$refs" "$newest" | hash)"
[ -n "$fp" ] || exit_ok

state="${INFRA_SIGNAL_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/infra-signal}"; sf="$state/${repo/\//__}"
[ "$(cat "$sf" 2>/dev/null)" = "$fp" ] && exit_ok                      # nothing changed since the last signal

code="$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl -q --noproxy '*' --proto =http -sS -K - --max-time 3 -o /dev/null -w '%{http_code}' \
  -X POST --data-binary "changed $repo" "$url" 2>/dev/null)" || exit_ok
case "$code" in 2??) mkdir -p "$state" 2>/dev/null && printf '%s\n' "$fp" > "$sf" 2>/dev/null ;; esac
exit_ok
