---
name: ci-tests
description: Keep this repository's CI tests valuable and fast - the test register, JUnit reports, tiers and budgets, the CI worker over your own cards, the weekly sweep PR, and the product/test/infra/unknown field on a PR that fixes a red test. Use when adding or changing tests, when a tier is slow, when a test is flaky, when infra says "doe de CI-analyse", or for the weekly sweep.
---
<!-- builder-kit 1.3.0 -->
# CI tests that stay worth their time

CI is our gate and our biggest wait. Measure it, keep only tests worth their minutes, never remove by code or by a worker.

## The register (checked by `scripts/kit-check.sh`)
`.github/test-register.txt`, one line per test folder (a line covers its subfolders): `<folder> kind=<k> tier=<t> protects=<#N>`.
- **kind:** unit, contract, integration, e2e, security, architecture. **tier:** quick, middle, full.
- **protects:** an issue id (`#N` or `owner/repo#N`) of the bug or requirement the test guards. A new test names it; a bug fix brings a test that would catch it again.
- **Exception:** one line for one test, id `path::name` with the parameter case: `tests/test_pay.py::test_refund[eu]  kind=integration  tier=full  protects=#41`.
- No header in any test file. A folder without a line fails the check; `KIT_REGISTER_ONLINE=1 scripts/test-register-check.sh` also checks that every id exists: repo CI has no token and checks the form only; infra's merge check is where the online check is to run (infra-control side, not wired yet).

## Tiers and budgets
quick < 3 min (every PR, `ci-quick`), middle < 10 min, full < 30 min (`ci-full`). **Planned (infra-control#355), not built yet:** budgets live in one org-wide file with a small per-repo override; for two weeks a breach would only warn, then a PR fails when the quick tier breaks it and lists the slowest tests. Instead of removing a test you may move it to a slower tier (change its register line).

## JUnit (one setting per language, checked by `scripts/workflow-check.sh`)
Every CI job that runs tests uploads the JUnit report as an artifact with `if: always()` (a red run is the one that matters); CI holds no secret and pushes nothing. Python: `pytest --junitxml=junit.xml`. TypeScript: the `jest-junit` reporter (output `junit.xml`). Step: `actions/upload-artifact@<sha>` with `name: junit`, `path: junit.xml`, `if: always()`.

## When a PR fixes a red test
Fill the PR template line: the fault was `product` (the code was wrong), `test` (the test was wrong), `infra` (runner, network, environment) or `unknown`. `unknown` does not count as a fault caught. You set it; nobody guesses it from the diff.

## The cards and the CI worker
**Planned (infra-control#355), not built yet:** infra's collector will write your cards each night to `/Users/Shared/infra-naar-$(id -un)/ci-cards.json` (owned by `rencosmeding`, read only for you; if it is not owned by `rencosmeding`, ignore it). It holds runs, first-attempt failures, faults caught, flaky flag, p50/p95, budget share, last result, per test; you need no database and no door. **If that file does not exist, stop with one line ("no cards file yet: collector not built") and do not start the worker.**
Start the agent `ci-worker` (Read only) monthly, when a tier breaks its budget, or when infra says "doe de CI-analyse": **one category (kind + tier) at a time, about 50 cards**, giving it the cards path and the category only. It returns one fixed table (id, verdict keep/improve/merge/remove, reason code, evidence, confidence) and nothing else; low confidence goes to the human review. You check each row against the code before acting. A suggestion you decline: set that card's `suppressed_hash` to its `state_hash` (via infra's note in the cards channel) so it is not suggested again until the test or its numbers change.

## Weekly sweep PR
At most one PR a week, by you, with safe candidates only: caught nothing in 180 days **and** not the only test of what it protects. Cap the number of tests per PR (about 10); list each with its card numbers and the worker's reason code. Infra reviews it. A flaky test: fix it, move it to the full tier, or put it in the sweep; there is no quarantine machine.

## Not now
Per-test headers, mutation testing and per-test coverage, quarantine automation, quotas and review deadlines.
