---
name: status-overview
description: Writes a builder's one-screen overview for its repository - what each job session does, what can start now, what waits on whom, its own to-dos - ending with one question to Renco. Use when Renco asks for an overview, status or "how is it going", and after a long stretch of work before handing back.
---
<!-- builder-kit 1.0.7 -->

# Status overview (one repository)

Same form as infra's overview, scoped to this repository. Cheap: one script run, no subagents, no transcripts, never from memory.

## 1. Gather
`scripts/ledger.sh overview` prints the plan (merged-not-verified, can start now, waiting on, decisions, open PRs), the running job sessions and the hygiene table. For a job session's detail read its issue or PR, not its conversation.

## 2. Write
In the language Renco uses now, plain words. One opening line: what moved since the last overview. Then, skipping empty parts:

| Job session / PR | Doing | Waiting on |
|---|---|---|
- Job: `<repo>-<N>` and the issue title. Doing: a few words (building / PR #n open / stopped). Waiting on: **Renco**, **infra**, another builder (name it), or nothing.

1. **Can start now**, in dependency order. Say which to start together; independent items never wait for each other.
2. **Waits on**: item <- blocker with its state; a blocked chain whose blocker is quiet is named as stalled.
3. **Merged, not verified**: each with what must be seen live.
4. **My to-dos**, numbered, most blocking first, one line each with the issue link.

End with **exactly one question** to Renco: the first item that needs him, with a short summary (what, why, risk, undo), the direct link, and my recommendation (yes / not yet / no, one line why). Several questions: the next only after his answer.

## Rules
- Links are full URLs to the right repository. No secrets, keys, IPs or emails.
- One screen; details stay in the issues. A to-do without an issue gets one first.
