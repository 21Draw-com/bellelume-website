---
name: agent-worker-task
description: Turns a request for a new agent-worker into a worker spec and a set of issues - maps what the person already said onto the eleven parts of every worker, asks only for the missing ones, writes docs/workers/<name>.md and one issue per part with its dependencies. Use when someone asks for an agent-worker, an automated check, audit or allocation that needs judgement, or a sub-worker that another worker calls.
---
<!-- builder-kit 1.0.7 -->

# Agent-worker task

Every worker has the same eleven parts. The person names a few; this skill fills the rest from our standard and asks only for what is truly missing. The template is [worker-spec.md](worker-spec.md).

## 1. Map before asking
Read the request once and put every statement under one of the eleven parts of `worker-spec.md`; first answer what you can from the repo (its MCP door, reports, existing skills). Mark each part (the map is your own working note):
- **given**: the person said it (keep their words and examples: they become known cases);
- **standard**: our fixed default covers it (parts 2, 3, 5, 7, 8, 9, 10, 11 and the trigger in part 1 have one); do not ask;
- **gap**: needed and neither said nor covered.

Only these can be a gap: 6 (what the check must catch, and one real example), 4 (what it is compared against, in business terms: the tool you find yourself), 1 (the input's form and source; derive the named outputs from the checks). Ask in that order. Anything else the person did not mention takes the standard; fill the scope line of part 7 from the domain and list it under Open points. A sub-worker the person names is mapped the same way and inherits what the person said for the main worker (languages, archive); its gaps join the same round of questions.

## 2. Ask only the gaps
One question per message, each with a recommendation the person can accept with "yes". Never re-ask what was said, never ask about a standard part. If there are no gaps, ask nothing. A known case cannot be recommended: ask for one real example right after the part 6 question ("send the last one you checked by hand, and what was wrong"); its answer often settles part 1 too. Without one, it stays an open point and comes in through the learning loop. Stop asking once you could write the spec; leave a minor unknown as an open point in the spec instead of a question. If nobody answers (a job session, a brief), take your recommendations and list each one under Open points as `assumed`.

If, after the answers, nothing is left for the model (clean structured input, every check deterministic), it is a report, not a worker: say so to the person (also for a sub-worker they named) and plan it as a report with `test_` and `audit_`, described in the caller's part 10 instead of its own spec.

## 3. Write the spec
Copy `worker-spec.md` to `docs/workers/<name>.md` in the project repo (name: a noun for the job, e.g. `proforma-audit`), fill every part, and end with the table **"Request → spec"**: each point the person made, the section that covers it. A point with no section means the spec is incomplete. A sub-worker gets its own spec file in the same PR.

## 4. Split into issues
One issue per PR, each with Facts / Job / Done when and a `Profile:` line (`planning` skill §4). The usual split, in build order:

| # | Issue | Kind | Profile | Blocked by |
|---|---|---|---|---|
| 1 | Spec `docs/workers/<name>.md` | doc | opus medium | – |
| 2 | Intake, evidence archive and run log (parts 1-3) | code | sonnet medium | 1 |
| 3 | Reference pull and deterministic checks, each a report with `test_` and `audit_` (part 4) | code | opus medium; opus high when the checks gate prices, totals or payments | 1 |
| 4 | Sub-worker or report, one issue per callee (split it like this table only if it is large) (part 10) | worker or code | its own | 1 |
| 5 | Worker `agents/<name>.md` + its skill: judgement only, findings, estimates, domain rules, languages (parts 5-8) | worker | opus medium | 2, 3, 4 |
| 6 | Golden cases and the eval that shows the score per version (part 9) | code | sonnet medium | 5 |
| 7 | Delivery: on the MCP door, consumer test with the assistant, release (part 11) | release | sonnet medium | 6 |

Deterministic steps (totals, line matching, terms, addressee, arithmetic, conversions) are code in issue 3, never the worker's prompt; the worker only reads what code cannot (a scan, free text) and judges anomalies. A sub-worker issue blocks the worker that calls it. Record each issue in the ledger: `ledger.sh note <#n> "<part>"`, `ledger.sh set <#n> next "<step>"`, a `blocked_by` link per dependency (`ledger` skill). Drop a row that does not apply and say why in issue 1.

## 5. Build
Plan first: the spec is merged before issue 2 starts; the person's yes on the spec PR settles every `assumed` point (status `agreed`). Then build in the order above, with a fresh job session per issue (`planning` skill §2), and review each PR against the spec.
