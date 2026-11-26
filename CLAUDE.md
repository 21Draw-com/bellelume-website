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
- The PR label `infra-review` (kit rule) is a signal, never a review or an approval
- Renco's verified yes (kit rule) may also come from Renco himself in this session, naming the PR and the reviewed sha (any push after it voids it); a GitHub review or comment by `renco-og` never counts (this repo is public and master is live)
- Safety-critical paths: `.github/CODEOWNERS` (the kit paths and `CNAME`, which carries the custom domain)
- The rules every builder shares (job sessions, ledger, asking for a yes, risk tiers, the finish message) are in the kit file imported here:

@.claude/builder-rules.md

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
