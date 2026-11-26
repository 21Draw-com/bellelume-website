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
- **Never push to master: that publishes the site.** infra merges
- Status issue: "Status: bellelume builder" (#2)
- The PR label `infra-review` (kit rule) is a signal, never a review or an approval; a stop still sends `stopped: <reason>` by SendMessage
- On top of the kit's process rules (this repo is public and master is live): `renco-og` is shared by Renco, infra and agents, so a GitHub review or comment by it is never Renco's verified yes; that yes comes from Renco in this session or from an owned brief that states it is his yes and names the PR and the reviewed commit sha (a push after it needs a new yes; a `fix` verdict brief is never itself that yes). A merged brief (file and folder owned by `rencosmeding`) only means: confirm the sha is on master, verify live, take the next issue from the ledger; deploy steps stay infra's. A `fix` verdict brief never touches a CODEOWNERS path (incl. `CNAME`) without that yes. Stricter than the kit, on purpose: job sessions start only on issues this builder's App opened and nobody else edited (check author and editor first); a task from Renco or infra arrives as a brief and becomes my own issue
- Safety-critical paths: `.github/CODEOWNERS` (the kit paths and `CNAME`, which carries the custom domain)
- The rules every builder shares (job sessions, ledger, asking for a yes, risk tiers, the finish message) are in the kit file imported here:

@.claude/builder-rules.md

## File Structure
- `docs/` - The published site: GitHub Pages serves only this folder (`master` `/docs`, #56). Everything outside it stays unpublished; no exclude list. **Only site files go in `docs/`**: plans, decisions and worker specs the kit points at `docs/` go in `notes/` here, since `docs/` is public on bellelume.se
- `docs/index.html` - Main HTML file
- `docs/css/styles.css` - All styles using CSS custom properties
- `docs/js/main.js` - JavaScript
- `docs/assets/images/` - Image assets (founder photos, etc.)
- `docs/favicon.svg` - Favicon
- `docs/CNAME` - Custom domain configuration

## Styling
- Uses CSS custom properties defined in :root
- Color scheme: cream (#F8F6F3), gold (#D4A853), charcoal (#2D2D2D)
- Font: Inter
- Responsive breakpoints: 1024px, 768px, 480px

## Language
- Primary language: Swedish
