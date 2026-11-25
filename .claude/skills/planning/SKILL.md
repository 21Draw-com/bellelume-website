---
name: planning
description: Guides how a builder plans and receives work - interview the person for an unclear request and write a spec, take a clear plan straight into issues without a new plan, research bigger jobs in plan mode, and review against the plan. Use when a request is unclear or large, when a plan arrives from infra or a person, and before reviewing finished work.
---
<!-- builder-kit 1.0.3 -->

# Planning

This skill carries Anthropic's own practice, nothing invented. Each part names its source (CC = code.claude.com/docs/en/best-practices, PM = code.claude.com/docs/en/permission-modes). Lines marked **ours** are our fixed points, with the reason.

## 1. Size decides the form
- **One PR:** the issue body is the plan (Facts / Job / Done when). Nothing more. Source: CC "Write a specific prompt" (name the file, the symptom, what "fixed" looks like). 
- **Several PRs or builders:** `docs/plans/YYYY-MM-DD-<subject>.md` in the repo where the work happens, linked from the issue; each other builder gets its part as an issue in its own repo, self-contained. Source: CC "Brainstorm with Claude first" (the spec is a file). **Ours:** GitHub is the source of truth and builders cannot read each other's repos, so no "read the other repo".
- A person reads an Artifact view of the Markdown; it never replaces the file. **Ours:** one source of truth.

## 2. Unclear request: interview, then spec
Ask the person what is missing, **one question at a time with a recommendation**, until you could write the spec; then write it to the plan file. The plan holds: goal; out of scope; steps, each one PR with a checkable "done when"; dependencies (`blocked_by`, `waits_on`); what needs a yes. Source: CC "Brainstorm with Claude first" (interview until you could write the spec, write SPEC.md). One-question-at-a-time and the recommendation are **ours** (Renco's rule: short decisions).
Then **a fresh session or job session builds from the file**, not the interview's context. Source: same section.
A request for an agent-worker uses the `agent-worker-task` skill instead: it asks only the gaps in the worker's eleven parts. **Ours.**

## 3. Bigger or unclear job: plan mode first
Research in plan mode (Shift+Tab, or `/plan`), propose, edit only after the plan is agreed. Source: PM "Analyze before you edit with plan mode". A one-line fix skips this.

## 4. Model and effort per job
The planner puts one line in each issue or plan step: `Profile: <model> <effort>`. Small and clear: `sonnet medium`. Normal: `opus medium`. Tricky (bugs in code nobody here wrote, schema changes, money/auth paths): `opus high`. `fable` only for the hardest work; `max` almost never. `scripts/job-session.sh` reads the line and starts the job with `--model` and `--effort`; no line means `sonnet medium`. The builder may raise it once, with the reason in the PR, and never lowers it silently. Source: CC "Change the model and effort" (effort is the main control; raise it where cases are easy to overlook, `max` tends to overthink ordinary work) and "Know what subagents cost". The four tiers are **ours** (one cheap default, escalation by a written line).

## 5. Receiving a plan: a checklist, not a new plan
Check it once against four points: a checkable "done when"? scope clear? dependencies named? no open questions? If all hold, turn it into issues (one per PR) and build. **Never write a plan for a plan.** If a point is missing, ask only that gap, then build. Note a disagreement once with a reason and follow the decision. Source: CC "Write a specific prompt" and "Give Claude a check to run"; the four points are **ours** (they are the concrete form of those two).

## 6. Working directly with a person
Same skill. The plan and issues are in GitHub, so infra sees them through the ledger; no message is needed. Cross-builder dependencies get `blocked_by` / `waits_on` (`ledger` skill). **Ours:** infra coordinates through GitHub.

## 7. Steering and review
- After two failed corrections: `/clear`, then one better prompt that folds in what was learned. Source: CC "Steer the session".
- Independent pieces of work run in parallel, one worktree each (`scripts/job-session.sh`). Source: CC "Run sessions in parallel".
- **Review against the plan with the `reviewer` subagent** (`.claude/agents/reviewer.md` from the builder kit: tools Read, Grep, Glob, model sonnet, so it cannot edit and has not seen how the code was written). Ask: "have the reviewer compare the change against <plan file or issue>". It checks that everything in "done when" is built and the listed edge cases have tests, and reports only gaps that affect correctness. **Skip style**: a reviewer asked to find problems always finds something. Source: CC "Review against your spec" and "Know what subagents cost" (the reviewer file is Anthropic's example; `model: sonnet` is **ours**, a cheap check).
- **Asking a person to approve** the result follows the rule in your CLAUDE.md: one question per message, the link, a plain summary, your recommendation after your own "why not" check; a "not yet" says what must happen first and who does it. **Ours** (Renco's approval rule).
- After the work: update the plan's status line (done / changed, with the PR); edit a changed plan in place, no copy. **Ours:** one plan, no drift.

## 8. What this skill does not do
No ALL-CAPS emphasis, "be thorough" or "keep going" lines in prompts it writes: current models do not need them (CC "What you can stop doing"). Rules that cannot bend become hooks, not louder text.
