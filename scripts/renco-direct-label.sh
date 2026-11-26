#!/bin/bash
# builder-kit 1.2.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# Creates (or updates) the label `renco-direct` in a builder repository: scripts/renco-direct-label.sh [owner/repo]
# No argument = the repository of origin. Idempotent. The label marks an issue or PR where the owner decided something
# directly with the builder (rule "Renco direct" in .claude/builder-rules.md); infra finds it by code (ledger.sh delta).
# Bounded (RENCO_GH_TIMEOUT, default 20 s). Not in the permission allow list: creating a label asks, once per repository.
set -u
slug="${1:-}"
if [ -z "$slug" ]; then
  slug="$(git config --get remote.origin.url 2>/dev/null | sed -nE 's#^(https://([^/@]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\3#p')"; slug="${slug%.git}"
fi
[[ "$slug" =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] || { echo "usage: renco-direct-label.sh [owner/repo]" >&2; exit 2; }
[ $# -le 1 ] || { echo "usage: renco-direct-label.sh [owner/repo]" >&2; exit 2; }
gh label create renco-direct --repo "$slug" --color 5319E7 --force \
  --description "Renco decided this directly with the builder; see the dated 'Renco direct' line" >/dev/null &
p=$!; { sleep "${RENCO_GH_TIMEOUT:-20}"; kill "$p"; } >/dev/null 2>&1 & w=$!
rc=0; wait "$p" 2>/dev/null || rc=$?; kill "$w" >/dev/null 2>&1 || true; wait "$w" 2>/dev/null || true
[ "$rc" = 0 ] && echo "label renco-direct ready in $slug" || { echo "could not create the label in $slug (exit $rc)" >&2; exit 1; }
