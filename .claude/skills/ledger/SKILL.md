---
name: ledger
description: Shows a builder its own work as a dependency tree that survives any restart - what can start now, what waits on whom, what merged but is not verified - and checks the repository's hygiene. Use at session start, when planning the next job, before saying anything is live, and when cleaning up an old backlog.
---
<!-- builder-kit 1.4.0 -->

# Ledger (builder mode)

Facts come from GitHub, notes from the store outside the tree (`$(git rev-parse --git-common-dir)/builder-ledger/notes.json`, one for the main clone and every worktree, never committed). Never from memory, never a second task list.
The script is `scripts/ledger.sh`, a kit file infra installs and updates; never edit it here (`scripts/kit-check.sh`).

## Every session
`scripts/ledger.sh show` (the SessionStart hook prints a short form). It lists, in this order:
1. **Merged, not verified**: leave it only with `ledger.sh verify <#n> "<what I saw live>"`. Until then never say "live".
2. **Can start now**: every blocker is closed. Independent items start side by side, each as its own job session (`scripts/job-session.sh start <N>`); two items are independent when neither blocks the other and the issues name no shared files. Dependent items wait for the blocker's merge.
3. **Waiting on**: item <- blocker with the blocker's live state. A blocker in another repository is a GitHub `blocked_by` link; where GitHub cannot link (another organisation) use `ledger.sh set <#n> waits_on <owner/repo#m>`. A person or agent that must act is a name: `waits_on renco`, `waits_on infra`.
4. **Decisions waiting for Renco**: say them, one at a time, with a recommendation.

## When a task arrives
Issue first, then `ledger.sh note <#n> "<text>"` and `ledger.sh set <#n> next "<next step>"`. After a context summary or restart: `show` before anything else.

## Hygiene
`scripts/ledger.sh hygiene` prints five rows, green / amber / red: open issues without a next step or blocker, untouched over 7 days, PRs open over 24 h, merged-not-verified, ledger adopted. Infra reads the same table. In idle time (never before live work or reports) fix the reds: close what is done or obsolete with the commit or the reason, give each remaining issue a next step or a blocker. Stop when no row is red.

## Rules
- The script reads GitHub only and never polls: it runs at session start, before planning, after a merge, or by hand.
- No secrets, names or private data in notes; they are committed.
