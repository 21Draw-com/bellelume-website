<!-- builder-kit 1.4.0 -->
## What and why
Closes #

## Checks
- Tier: small | normal | risky (`.claude/builder-rules.md`, Quality by risk tier)
- Tests: <command> → <result>
- Reviewer: <findings and what I did, or "none">
- Security reviewer (normal, risky): <findings and what I did, or "none">
- Safety-critical paths touched: none | <paths> (then the PR waits for the owner's verified yes)
- If this PR fixes a red test, the fault was: product | test | infra | unknown (`unknown` does not count as a fault caught), else "n/a"
- Same PR: a decision file (not under `docs/`: that folder is the published site, see `CLAUDE.md`) / "Timed behaviour" / "What runs" updated, or "not needed"
- Pre-flight: `scripts/preflight.sh <PR>` → GREEN (label `infra-review` only then)

## For Renco
<a question for the owner (what, why, risk, undo, my recommendation) and the label `vraag-renco`; "nothing" if nothing>

## For infra after the merge
<what infra must run, restart, roll out or verify live; "nothing" if nothing>

## Learnings for all agents?
<"no", or one line per learning>
