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

## Tell infra when done (infra-control#151, 2026-11-24)
The last step of every job (every PR opened, every review round, every stop): send ONE message to the session **infra-control** with the SendMessage tool:
`PR <full link> ready for review` (or: `stopped: <reason, one line>`).
Find the name with ListAgents if needed. One line, nothing else; no secrets. It is information for infra, not a request to do anything.

## Job sessions (infra-control#147, 2026-11-24)
The main builder coordinates. Each **independent** issue (no blocked_by/waiting on another, no shared files) runs as its own visible Claude Remote session `<repo>-<N> <title>`, in its own worktree, at most 3 at once. Each one opens ONE PR and messages infra-control when done.
- Start from the main clone: `bash scripts/job-session.sh start <N>` (`--dry-run` first; `list`; `close <N>` after its PR).
- Own role of the main builder: review the job PRs (QA for their tier), keep the status issue current, report each job PR to infra. Dependent issues wait for their blocker's merge.
- Note: the script assumes the default branch is `main`; this repo uses `master` (open point with infra).

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
