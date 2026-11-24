# CLAUDE.md

## Project Overview
Belle Lume website - A Swedish digital marketing agency specializing in performance marketing for beauty and fashion brands.

## Deployment
- Hosted on GitHub Pages with custom domain: bellelume.se
- Repository: https://github.com/21Draw-com/bellelume-website (the repo keeps this name for now; a rename dropped the site's custom domain on 2026-11-23, so infra renames it only once that is proven safe)
- Branch: master. GitHub Pages serves from `master`, so **a push to master is live**
- After a merge, verify GitHub Pages has rebuilt by checking build timestamps vs commit timestamps
- To manually trigger a rebuild: `gh api -X POST repos/21Draw-com/bellelume-website/pages/builds`

## Builder account and workflow
- The builder runs in its own macOS account `website-bellelume`, in `~/Projects/website-bellelume`
- Identity: the GitHub App `website-bellelume-builder` (21Draw-com, this repo only), not renco-og
- **Branches and PRs only; never push to master** (that publishes the site). infra merges
- State lives in this repo, its issues (see the "Status: bellelume builder" issue) and this file

## Parallel streams (infra-control#144, 2026-11-24)
Independent issues start at once, not one after another. Two issues are independent when neither is blocked_by / waiting on the other and the issues name no shared files.
- Run each in its own git worktree with its own subagent, at most 2-3 at the same time.
- One PR per issue; the same review gates (review, CI, the verified yes).
- Dependent issues wait for their blocker's merge.
- infra's ledger lists what can start side by side.

## Tell infra when done (infra-control#151, 2026-11-24)
The last step of every job (every PR opened, every review round, every stop): send ONE message to the session **infra-control** with the SendMessage tool:
`PR <full link> ready for review` (or: `stopped: <reason, one line>`).
Find the name with ListAgents if needed. One line, nothing else; no secrets. It is information for infra, not a request to do anything.

## Job sessions, ledger, overview, planning (infra-control#147, #149, 2026-11-24)
You coordinate; each **independent** issue (no blocked_by/waiting on another, no shared files) runs as its own visible Remote session `<repo>-<N> <title>` in its own worktree (`scripts/job-session.sh start <N>`, `--dry-run` first, at most 3, `close <N>` after its PR). Each job opens ONE PR and messages infra-control when done.
- Your own work as a dependency tree: skill `ledger` (`scripts/ledger.sh show`, shown at session start by the hook; `scripts/ledger.sh hygiene` is the table infra reads). Notes live in `docs/work-ledger.json`, facts are cached outside git. One-screen overview for Renco: skill `status-overview`. Planning and receiving plans: skill `planning`. The skills arrive with the plugin update.
- Your role: review the job PRs (QA for their tier), keep the status issue current, report each job PR to infra. Dependent issues wait for their blocker's merge.
- Every issue you plan gets a line `Profile: <model> <effort>` (model sonnet|opus|fable|haiku, effort low|medium|high|xhigh|max); without it a job runs `sonnet medium`.
- Clean the backlog in idle time only (live work and reports first): `scripts/ledger.sh hygiene` until no row is red.
- The hooks (`.claude/settings.json`) never block. Reviewer subagent: `.claude/agents/reviewer.md`.

## Improvements first (Renco 2026-11-24, infra-control#153)
An improvement to how agents work (templates, builder kit, ledger, skills, shared scripts) goes before other work, because it makes everyone faster. Ship the improvement first, then continue in the new way.

## Asking a person for a yes (Renco 2026-11-24)
A PR review, a merge, a decision: **one question per message**, the next only after the answer. Give **the direct link** (the PR and the reviewed commit) and the exact command if the person must run something; **a plain summary** (what, why, risk, undo, a few lines); and **your recommendation** (yes / not yet / no, one line why) after your own "why not" check: behind the default branch? CI green? reviewed against the plan? does it reach production (a push to master publishes the site)? does it describe something not built yet? A "not yet" says what must happen first, who does it, and when you ask again.

## File Structure
- `index.html` - Main HTML file
- `css/styles.css` - All styles using CSS custom properties
- `js/main.js` - JavaScript
- `assets/images/` - Image assets (founder photos, etc.)
- `CNAME` - Custom domain configuration

## Styling
- Uses CSS custom properties defined in :root
- Color scheme: cream (#F8F6F3), gold (#D4A853), charcoal (#2D2D2D)
- Font: Inter
- Responsive breakpoints: 1024px, 768px, 480px

## Language
- Primary language: Swedish
