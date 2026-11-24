# Worker spec: <name>

Status: draft | agreed | built (PR) · Project: <repo> · Requested by: <person>, <date>
One sentence: what the worker does, for whom.

Fill each part in a few lines. Where a part says **Standard**, keep it unless the person said otherwise.

## 1. Contract
- **Input:** <what arrives, format (PDF scan, CSV, MCP record id), who sends it>
- **Output:** one JSON result, schema in `agents/<name>.md`. Named outputs: <e.g. `verdict`, `findings[]`, `estimated_container`>
- **Trigger:** **Standard:** the assistant (or infra) starts it with one named task. Otherwise: <a *changed* event | another worker>

## 2. Evidence archive
**Standard:** every input is stored unchanged by the product, under `<data dir>/evidence/<run-id>/`, with its sha256; kept <how long, default 2 years>, backed up with the product's data, never in git. The worker gets the path or hash, never a copy to keep.

## 3. Run log
**Standard:** one record per run, written by the product (`log_run` on the MCP door): run id, task, worker version, model, prompt, reasoning summary, input hashes or paths, every data pull (tool, arguments, as-of), output, verdict, duration. Never secrets or full personal data. Purpose: evaluate, reclassify, replay a run that went wrong.

## 4. Deterministic first
- **Reference data:** <which report or MCP tool, which fields>. The pull is checked before use (record found, as-of fresh, counts match).
- **Code checks:** <list, e.g. totals, line count and quantities against the order, Incoterms (FOB/CFR/EXW), addressee, shipping stated separately>
- **Tolerance:** <exact, or e.g. 0.01 per line for rounding>
- **Left to the model:** <only what code cannot: reading a scan, judging an anomaly>

## 5. Findings and severity
**Standard:** every difference is a finding with severity `stop` (contract broken, input unreadable, reference missing), `warning` (any difference: "needs further research") or `info`. Nothing is passed silently; a run with a `stop` or `warning` never has verdict `ok`.

## 6. Domain rules and known cases
- **Rules:** <the checks in plain words>
- **Known cases:** <earlier cases, e.g. "1 container row" = shipping on one line, not per item>
Kept in the worker's skill; a new case is a line here and a golden case (part 9).

## 7. Estimates and scope
**Standard:** missing data may be estimated from what was learned, always marked `estimate: true` with its basis (e.g. "a list price is not a price until the pro-forma"). Costs outside the scope are named, not computed: <e.g. Cuba → warehouse is not in this invoice>; when the person named none, fill them from the domain and list them under Open points.

## 8. Languages
**Standard:** English. Other languages only when the person named them: <e.g. English + Turkish>. Field names stay English; texts for people in each language.

## 9. Learning loop
**Standard:** golden cases in `tests/workers/<name>/` (input + expected output). Every correction a person makes is logged against the run id and becomes a golden case. `eval_<name>` replays all cases; the score per worker version is shown in the release notes.

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
