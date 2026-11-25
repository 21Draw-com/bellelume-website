<!-- builder-kit 1.0.3 -->
# Worker spec: <name>

Status: draft | agreed | built (PR) · Project: <repo> · Requested by: <person>, <date>
One sentence: what the worker does, for whom.

Fill each part in a few lines. Where a part says **Standard**, keep it unless the person said otherwise.

## 1. Contract
- **Input:** <what arrives, format (PDF scan, CSV, MCP record id), who sends it>
- **Output:** one JSON result. **Standard:** the schema lives in code (`agent/workers.py` `Result`: `verdict`, `findings[]` with `severity`, `estimate` and `basis`, `report_refs`, `gaps`, `improvements`, `note`), and the definition `agents/<name>.md` shows the same fields (a test holds them together). Named outputs beyond it: <e.g. `estimated_container`>. What a person sees is a pure page made from that result by code (`workers.page`), never text the model wrote for the page.
- **Proposals:** **Standard:** the worker may prepare one with a `prepare_<kind>` tool; only a person's verified yes carries it out (`scripts/yes`), never the worker.
- **Trigger:** **Standard:** the assistant (or infra) starts it with one named task. Otherwise: <a *changed* event | another worker>
- **Budget:** **Standard:** 30 turns (`maxTurns`), 15 minutes (the start script ends the session), 2 USD (declared, read in the monthly review), stored-only door (its tools answer from stored data: no live read, scrape or paid call on its behalf), and its kill flag `<plugin>-worker.off` stops it from starting (a flag set during a run does not stop it: infra ends it with `tmux kill-session`). Otherwise: <why this worker needs more>

## 2. Evidence archive
**Standard:** every input is stored unchanged by the product, under `<data dir>/evidence/<run-id>/`, with its sha256; kept <how long, default 2 years>, backed up with the product's data, never in git. The worker gets the path or hash, never a copy to keep.

## 3. Run log
**Standard:** one row per run in the work log (`worklog_tasks`, written by `record_task`; no second log; the run id comes from `start_run` at the start, and a second `record_task` with it replaces the row, so the logged output is the one returned): run id, task, worker, worker version and prompt version (computed by the product), model, reasoning summary, input hashes or paths, output, output problems (the output checked against the schema), verdict, turns. Every data pull is its own row in `worklog_calls` (tool, arguments, outcome, duration), written by the product. Each judgement on one input is a row in `worklog_opinions` (`record_opinion`: classifier, prompt version, input hash, label, confidence). Secrets are withheld. Purpose: evaluate, reclassify, and replay a run by its id: `replay_<worker>(run_id)` re-runs the deterministic part from the stored row, a model run is started again on the same task and compared (`python -m agent.replay`).

## 4. Deterministic first
- **Reference data:** <which report or MCP tool, which fields>. The pull is checked before use (record found, as-of fresh, counts match).
- **Code checks:** <list, e.g. totals, line count and quantities against the order, Incoterms (FOB/CFR/EXW), addressee, shipping stated separately>
- **Tolerance:** <exact, or e.g. 0.01 per line for rounding>
- **Input keys:** every key the code reads from a source is listed in `workers.INPUT_KEYS` and checked against that source's recorded answer, so a renamed field fails a test first (input key drift).
- **Left to the model:** <only what code cannot: reading a scan, judging an anomaly>
- **Two-pass agreement:** <only when the findings gate money: two independent runs on the same input, `workers.agree` keeps what both found and turns a disagreement into a `warning`; otherwise "none">

## 5. Findings and severity
**Standard:** every difference is a finding with severity `stop` (contract broken, input unreadable, reference missing), `warning` (any difference: "needs further research") or `info`; these three words and no others. Nothing is passed silently. The verdict is the highest severity (`ok` when none is above `info`), computed by code (`workers.verdict_of`; the work log stores code's verdict, never the model's): a run with a `stop` or `warning` never has verdict `ok`, and `record_task` logs a mismatch as an output problem.

## 6. Domain rules and known cases
- **Rules:** <the checks in plain words>
- **Known cases:** <earlier cases, e.g. "1 container row" = shipping on one line, not per item>
Kept in the worker's skill; a new case is a line here and a golden case (part 9).

## 7. Estimates and scope
**Standard:** missing data may be estimated from what was learned; code computes the estimate and labels it (`reports.estimated(value, basis)`, e.g. basis "a list price is not a price until the pro-forma"), and the report says so in its notes. The worker never estimates: it carries the estimate through with `estimate: true` and the report's basis. Costs outside the scope are named, not computed: <e.g. Cuba → warehouse is not in this invoice>; when the person named none, fill them from the domain and list them under Open points.

## 8. Languages
**Standard:** English. Other languages only when the person named them: <e.g. English + Turkish>. Field names stay English; texts for people in each language.

## 9. Learning loop
**Standard:** every correction a person makes is logged against the run id and **becomes a rule first**: a check in code with its test, wherever code can catch it. Then it is a golden case in the agent's own database (`worklog_golden`, `python -m agent.replay golden`), with that rule or why no rule can catch it. Golden cases hold business data, so they never go into git; `tests/data/workers/` holds invented outputs only, which test the schema. The eval (`python -m agent.replay eval`) runs every golden case again; the score per worker version is shown in the release notes. **Graduation:** an answer a person approved that keeps coming back becomes a report (`report_<name>`, deterministic, with `test_` and `audit_`); the worker then only cites it.

## 10. Sub-workers
**Standard:** none, unless the person named one: <name: what it returns, its own spec `docs/workers/<sub>.md`>. Each has its own contract; its issue blocks this worker.

## 11. Delivery
**Standard:** spec agreed → build (issues) → exposed on the agent's MCP door → consumer test (the personal assistant asks a typical question) → release in the `avanzanova` marketplace.

## Open points
<minor unknowns, who answers them>

## Request → spec
| Point the person made | Section |
|---|---|
| | |
