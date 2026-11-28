#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Portable helpers (kit 1.4.0, infra-control#356/#367 item 12): GNU first, BSD (macOS) fallback, so a script runs the same
# on the Linux CI runner and on the Mac. Source it:  . "$(dirname "$0")/portable.sh"   (tests: . "<kit>/scripts/portable.sh")
# scripts/portability-check.sh flags the raw calls these replace (stat -f/-c, date -v/-j/-d, sed -i, base64 -D, grep -P,
# find -printf, /opt/homebrew/bin/<tool>) everywhere except in this file.
#   file_owner <path>            user name of the owner
#   file_mode <path>             permission bits in octal, e.g. 644
#   file_mtime <path>            modification time, seconds since the epoch
#   date_from_epoch <s> [fmt]    format an epoch in UTC (default %Y-%m-%dT%H:%M:%SZ)
#   epoch_from_date <YYYY-MM-DD> midnight UTC of that day, seconds since the epoch
#   days_ago <n> [fmt]           the UTC date n days ago (default %Y-%m-%d)
#   sed_inplace <sed args...> <file>   in-place edit, no backup file left
#   b64_decode                   base64 decode stdin to stdout
file_owner() { stat -c %U "$1" 2>/dev/null || stat -f %Su "$1"; }
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
date_from_epoch() { local f="+${2:-%Y-%m-%dT%H:%M:%SZ}"; date -u -d "@$1" "$f" 2>/dev/null || date -u -r "$1" "$f"; }
epoch_from_date() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s; }
days_ago() { date_from_epoch "$(( $(date -u +%s) - $1 * 86400 ))" "${2:-%Y-%m-%d}"; }
sed_inplace() { local f="${*: -1}" t; t="$(mktemp "${f}.XXXXXX")" || return 1; sed "${@:1:$#-1}" "$f" > "$t" && cat "$t" > "$f"; local rc=$?; rm -f "$t"; return $rc; }
b64_decode() { if printf 'eA==' | base64 -d >/dev/null 2>&1; then base64 -d; else base64 -D; fi; }
