#!/bin/bash
# builder-kit 1.3.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# CI workflow lint (kit 1.2.0, hardened in 1.2.1; AGENT-ARCHITECTURE.md §1.18): every workflow in .github/workflows must follow the CI rules.
#   scripts/workflow-check.sh [repo dir]      (no network, read-only; exit 0 = holds, 1 = a finding, each printed as FAIL)
# Rules (FAIL): no pull_request_target, workflow_run, issue_comment, issues, pull_request_review_comment, discussion or discussion_comment trigger (read from `on:` in all three forms: scalar, list, map); a top-level `permissions:` with `contents: read` and no
# write at the top; every action pinned to a full commit SHA; every actions/checkout with `persist-credentials: false`;
# no `${{ }}` expression in a `run:` or `script:` (actions/github-script) value except an allow list (env.*, secrets.*,
# matrix.*, runner.*, github.sha, github.run_id, github.repository): everything else, event data, inputs.*, steps/needs outputs,
# toJSON/format, github['event'], is flagged (pass it through `env:`); the whole value is read as written (comments inside a run
# body count, multi-line plain scalars count); a workflow that runs on pull_request has `cancel-in-progress: true` (or `${{ github.event_name == 'pull_request' }}`, nothing else), no
# `permissions: write-all` and no job-level `contents: write` (1.2.1). NOTE (not a FAIL): a path filter on a pull_request trigger (a required
# check that a filter skips stays pending: use the always-run docs-only step of §1.18 instead).
# Second narrow escape, workflow_run only (never pull_request_target or issue_comment): a GitHub-hosted workflow that never checks out or runs
# github.event.workflow_run.head_* code carries
#   # workflow-check: allow workflow_run (GitHub-hosted, no checkout or run of github.event.workflow_run.head_* code, <reason>)
# honoured only when EVERY `runs-on:` in the file is a literal ubuntu-*, windows-* or macos-* label (1.2.1: `[ci]`, a runner group, a
# `${{ matrix.x }}` or a missing runs-on can still be self-hosted); printed as a NOTE. The lint cannot check the head_* condition: infra reviews such a workflow by hand.
# One narrow escape: a GitHub-hosted release/deploy job that must push keeps its checkout credentials. The file carries the marker
#   # workflow-check: allow persist-credentials (release, GitHub-hosted, <reason>)
# honoured under the same every-runs-on-is-literal rule; printed as a NOTE. The lint reads workflow text only: it does not judge where
# a job runs, so a project's own runner on its own server is left alone (infra checks that box and its hooks).
# run: counts as a script only as a step key, script: only under a step's `with:` (a job `outputs:`, `env:` or `defaults:` key named run: is data).
# Kit 1.3.0 (infra-control#354): a job that runs tests (pytest, jest, vitest, npm/pnpm/yarn test) uploads its JUnit report: an actions/upload-artifact step with a junit path and `if: always()`; a direct pytest has `--junitxml`, a direct jest `jest-junit`.
# Accepted gaps (1.2.1, not seen by the lint, infra reviews them by hand): steps written as flow mappings (`- {run: echo x}`) and quoted
# keys (`"run":`, `'script':`).
# Accepted false positives (rewrite the line, never silence the lint): a safe numeric field such as github.event.pull_request.number
# inside `run:` is flagged (put it in `env:`); inline flow permissions (`permissions: {contents: read}`) are flagged (use the block form).
root="$(cd "${1:-.}" 2>/dev/null && { git rev-parse --show-toplevel 2>/dev/null || pwd; })" || { echo "FAIL workflow-check: no such directory" >&2; exit 1; }
cd "$root" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "FAIL workflow-check: python3 needed"; exit 1; }
python3 -I - "$root" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
out, bad = [], False
def indent(l): return len(l) - len(l.lstrip(" "))
def parse_on(code):
    """The set of event names under the top-level `on:`, from the scalar, list and map forms (block or inline)."""
    names = set()
    for i, l in enumerate(code):
        m = re.match(r"""(?:on|"on"|'on')\s*:\s*(.*)$""", l)
        if not m: continue
        rest = m.group(1).strip()
        clean = lambda t: t.strip().strip("'\"")
        if rest.startswith("[") or rest.startswith("{"):
            buf, j = rest, i
            while buf.count("[") + buf.count("{") > buf.count("]") + buf.count("}") and j + 1 < len(code):
                j += 1; buf += " " + code[j].strip()
            if rest.startswith("["):
                names |= {clean(x) for x in buf.strip()[1:buf.rindex("]")].split(",") if x.strip()}
            else:
                depth, cur = 0, ""
                for ch in buf:
                    if ch in "{[": depth += 1; cur += ch if depth > 1 else ""
                    elif ch in "}]": depth -= 1; cur += ch if depth >= 1 else ""
                    elif ch == "," and depth == 1: cur += "\0"
                    else: cur += ch if depth >= 1 else ""
                for part in cur.split("\0"):
                    k = re.match(r"\s*['\"]?([A-Za-z_]+)['\"]?\s*:", part)
                    if k: names.add(k.group(1))
        elif rest:
            names |= {clean(x) for x in rest.split(",") if x.strip()}
        else:
            child = None
            for l2 in code[i + 1:]:
                if l2.strip() == "": continue
                if indent(l2) == 0: break
                if child is None: child = indent(l2)
                if indent(l2) != child: continue
                k = re.match(r"\s*(?:-\s*)?['\"]?([A-Za-z_]+)['\"]?\s*:?", l2)
                if k: names.add(k.group(1))
        break
    return names
def literal_hosted(code):
    """True only when the file has runs-on and every one is a literal ubuntu-*/windows-*/macos-* label."""
    vals = [m.group(1).strip().strip("'\"") for m in (re.match(r"\s*(?:-\s*)?runs-on\s*:\s*(.*)$", l) for l in code) if m]
    return bool(vals) and all(re.fullmatch(r"(ubuntu|windows|macos)-[A-Za-z0-9._-]+", v) for v in vals)
def key_parent(lines, k, kcol, dash):
    """('step'|'with'|'other', name): where the key on line k lives. 'step' = a key of a map that is an item of `steps:`."""
    def seq_parent(d):                                   # the key that owns the list whose items start at column d
        for j in range(k_start - 1, -1, -1):
            t = lines[j]
            if t.strip() == "" or t.lstrip().startswith("#"): continue
            if indent(t) < d or (indent(t) == d and not t.lstrip().startswith("-")):
                m = re.match(r"\s*['\"]?([A-Za-z0-9_-]+)['\"]?\s*:", t); return m.group(1) if m else ""
        return ""
    if dash is not None: k_start = k; return ("step", seq_parent(dash)) if seq_parent(dash) == "steps" else ("other", seq_parent(dash))
    for j in range(k - 1, -1, -1):
        t = lines[j]
        if t.strip() == "" or t.lstrip().startswith("#"): continue
        if indent(t) < kcol:
            if t.lstrip().startswith("-"):
                k_start = j; sp = seq_parent(indent(t)); return ("step", sp) if sp == "steps" else ("other", sp)
            m = re.match(r"\s*['\"]?([A-Za-z0-9_-]+)['\"]?\s*:", t); return ("with" if m and m.group(1) == "with" else "other", m.group(1) if m else "")
    return ("other", "")
SAFE_EXPR = re.compile(r"\s*(env\.[A-Za-z_][A-Za-z0-9_]*|secrets\.[A-Za-z0-9_]+|matrix\.[A-Za-z0-9_.-]+|runner\.[A-Za-z_]+|github\.(sha|run_id|repository))\s*")
files = sorted(glob.glob(os.path.join(root, ".github/workflows/*.y*ml")))
for path in files:
    wf = os.path.relpath(path, root)
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    raw_text = "\n".join(lines)
    escape_wr = re.search(r"#\s*workflow-check:\s*allow workflow_run\s*\(GitHub-hosted, no checkout or run of github\.event\.workflow_run\.head_\* code, [^)]+\)", raw_text)
    escape = re.search(r"#\s*workflow-check:\s*allow persist-credentials\s*\(release, GitHub-hosted, [^)]+\)", raw_text)
    code = [re.sub(r"(^|\s)#.*$", "", l) for l in lines]          # comments never count
    text = "\n".join(code)
    hosted = literal_hosted(code)
    def fail(n, msg):
        global bad; bad = True; out.append(f"FAIL {wf}{':%d' % n if n else ''}: {msg}")
    triggers = parse_on(code)
    for bad_t in ("pull_request_target", "workflow_run", "issue_comment", "issues", "pull_request_review_comment", "discussion", "discussion_comment"):
        if bad_t == "workflow_run" and bad_t in triggers and escape_wr and hosted:
            out.append(f"NOTE {wf}: workflow_run allowed by the documented marker (GitHub-hosted, no head_* code); the lint cannot check that condition: infra reviews this workflow by hand")
        elif bad_t in triggers:
            fail(0, f"trigger {bad_t}: it runs with write rights or secrets on untrusted input (use pull_request)")
    # top-level permissions
    top = [i for i, l in enumerate(code) if re.match(r"permissions\s*:", l)]
    if not top:
        fail(0, "no top-level `permissions:` (add `contents: read`; widen per job only)")
    else:
        i = top[0]; rest = code[i].split(":", 1)[1].strip()
        if rest:
            if rest not in ("read-all", "{}"): fail(i + 1, f"top-level permissions `{rest}`: use a block with `contents: read`")
        else:
            block = []
            for l in code[i + 1:]:
                if l.strip() == "": continue
                if indent(l) == 0: break
                block.append(l.strip())
            if "contents: read" not in block: fail(i + 1, "top-level permissions lack `contents: read`")
            if any(re.search(r":\s*write\b", b) for b in block): fail(i + 1, "top-level permissions grant write: widen only in the job that needs it")
    for n, l in enumerate(code, 1):
        m = re.match(r"\s*(?:-\s*)?uses\s*:\s*['\"]?([^\s'\"]+)", l)
        if m:
            ref = m.group(1)
            if not (ref.startswith("./") or re.search(r"@[0-9a-f]{40}$", ref) or re.match(r"docker://.+@sha256:[0-9a-f]{64}$", ref)):
                fail(n, f"{ref} is not pinned to a full commit SHA (`@<sha> # <tag>`)")
            if re.match(r"actions/checkout@", ref):
                kcol = l.index("uses")
                dash = l[:kcol].rstrip().endswith("-")
                d = (kcol - 2) if dash else None
                if d is None:                                      # `uses` is a key below the dash line: find the dash
                    j = n - 2
                    while j >= 0 and not (code[j].lstrip().startswith("-") and indent(code[j]) < kcol): j -= 1
                    d = indent(code[j]) if j >= 0 else 0
                end = n
                while end < len(code) and (code[end].strip() == "" or indent(code[end]) > d): end += 1
                if not re.search(r"persist-credentials\s*:\s*['\"]?false", "\n".join(code[n - 1:end])):
                  if escape and hosted:
                    out.append(f"NOTE {wf}:{n}: checkout keeps its credentials by the documented release escape (GitHub-hosted release/deploy job that must push)")
                  else:
                    fail(n, "actions/checkout without `persist-credentials: false` (the job token would stay in .git/config)")
    # run: and script: values: read from the RAW lines (a comment inside a shell body is still shell), continuation lines of a
    # plain or quoted scalar count, and any ${{ }} outside the allow list is a script injection (1.2.1).
    k = 0
    while k < len(lines):
        m = re.match(r"(\s*)(-\s*)?(run|script)\s*:\s*(.*)$", lines[k])
        if m:
            col = len(m.group(1)) + (len(m.group(2)) if m.group(2) else 0)
            first = m.group(4)
            kind, _pk = key_parent(lines, k, col, len(m.group(1)) if m.group(2) else None)
            # run: is a script only as a step key; script: only under a step's with: (any action: some run it as shell, e.g. ssh actions).
            # A job `outputs:` key named run:, an env: or defaults: key are plain data (infra verdict on templates#197).
            if not (kind == "step" and m.group(3) == "run" or kind == "with" and m.group(3) == "script"):
                k += 1; continue
            body = [(k + 1, first)]
            j = k + 1
            while j < len(lines) and (lines[j].strip() == "" or indent(lines[j]) > col): body.append((j + 1, lines[j])); j += 1
            k = j - 1
            for n, b in body:
                for e in re.finditer(r"\$\{\{(.*?)\}\}", b):
                    if not SAFE_EXPR.fullmatch(e.group(1)):
                        fail(n, "`${{ %s }}` inside a `%s:` value is a script injection: pass it through `env:` and use the variable (allowed: env.*, secrets.*, matrix.*, runner.*, github.sha, github.run_id, github.repository)" % (e.group(1).strip(), m.group(3)))
        k += 1
    if "pull_request" in triggers:
        for n, l in enumerate(code, 1):
            if re.match(r"\s*permissions\s*:\s*write-all\b", l) or (indent(l) > 0 and re.match(r"\s*contents\s*:\s*write\b", l)):
                fail(n, "a pull_request workflow grants write (`write-all` or `contents: write`): a PR from a fork or a compromised branch gets it; move the write to a push/release workflow")
        if not re.search(r"(?m)cancel-in-progress\s*:\s*['\"]?(true|\$\{\{\s*github\.event_name\s*==\s*'pull_request'\s*\}\})['\"]?\s*$", text):
            fail(0, "runs on pull_request without `concurrency: cancel-in-progress: true` (a superseded run keeps a runner busy)")
        m = re.search(r"^\s*pull_request\s*:\s*\n((?:\s+.*\n?)*)", text, re.M)
        if m and re.search(r"^\s+paths(-ignore)?\s*:", m.group(1).split("\n  push")[0], re.M):
            out.append(f"NOTE {wf}: a path filter on pull_request: a required check it skips stays pending (use the docs-only step, §1.18)")
    # Kit 1.3.0 (infra-control#354, plan §2): a job that runs tests uploads its JUnit report (the collector reads it, CI holds no secret).
    ji = next((i for i, l in enumerate(code) if re.match(r"jobs\s*:\s*$", l)), None)
    if ji is not None:
        jcol, jobs, cur = None, [], None
        for i in range(ji + 1, len(code)):
            l = code[i]
            if l.strip() == "": continue
            if indent(l) == 0: break
            if jcol is None: jcol = indent(l)
            if indent(l) == jcol and re.match(r"\s*['\"]?[A-Za-z0-9_-]+['\"]?\s*:", l): cur = [i, []]; jobs.append(cur)
            if cur: cur[1].append((i + 1, l))
        def words(l):
            """The command word and its tail of each command in a line (after run:, &&, ;, |, python -m, npx, uv/poetry run): an install argument is never one."""
            l = re.sub(r"^\s*(-\s*)?(run\s*:)?\s*[|>][-+]?\s*$", "", l)
            l = re.sub(r"^\s*(-\s*)?(run\s*:\s*)?", "", l)
            for seg in re.split(r"&&|\|\||;|\|", l):
                t = seg.split()
                while t and re.match(r"[A-Za-z_][A-Za-z0-9_]*=", t[0]): t = t[1:]
                while t and (t[0] in ("npx", "exec", "time") or re.fullmatch(r"python3?(\.\d+)?", t[0]) and t[1:2] == ["-m"] or t[:2] in (["uv", "run"], ["poetry", "run"], ["pipenv", "run"])):
                    t = t[2:] if t[0].startswith("python") else t[2:] if t[0] in ("uv", "poetry", "pipenv") else t[1:]
                if t: yield t
        def testcmd(l):
            for t in words(l):
                if t[0] in ("pytest", "py.test", "jest", "vitest"): return t[0]
                if t[0] in ("npm", "pnpm", "yarn") and (t[1:2] in (["test"], ["t"]) or t[1:3] in (["run", "test"], ["run", "t"])): return t[0]
            return None
        for _, blk in jobs:
            body = [(n, l) for n, l in blk if not re.match(r"\s*(-\s*)?(name|if|id|key)\s*:", l) and "uses:" not in l]
            btext = "\n".join(l for _, l in blk)
            hit = next(((n, m) for n, l in body for m in [testcmd(l)] if m), None)
            if not hit: continue
            n0 = hit[0]
            if any(testcmd(l) in ("pytest", "py.test") for _, l in body) and "--junitxml" not in btext:
                fail(n0, "a job runs pytest without `--junitxml=<file>` (kit 1.3.0: one JUnit setting per language)")
            if any(testcmd(l) == "jest" for _, l in body) and "jest-junit" not in btext:
                fail(n0, "a job runs jest without the `jest-junit` reporter (kit 1.3.0: one JUnit setting per language)")
            ups = [i for i, (n, l) in enumerate(blk) if re.search(r"uses\s*:\s*['\"]?actions/upload-artifact@", l)]
            def step_of(i):
                d = None
                for j in range(i, -1, -1):
                    if blk[j][1].lstrip().startswith("-"): d = indent(blk[j][1]); k0 = j; break
                else: return blk[i][1]
                e = k0 + 1
                while e < len(blk) and (blk[e][1].strip() == "" or indent(blk[e][1]) > d): e += 1
                return "\n".join(l for _, l in blk[k0:e])
            if not any(re.search(r"junit", step_of(i), re.I) and re.search(r"if\s*:\s*['\"]?(\$\{\{\s*)?always\(\)", step_of(i)) for i in ups):
                fail(n0, "a job runs tests but no `actions/upload-artifact` step with a JUnit path and `if: always()` follows (kit 1.3.0: a red run is the one to report)")
print("\n".join(out))
sys.exit(1 if bad else 0)
PY
rc=$?
[ $rc = 0 ] && echo "workflow-check: workflows hold"
exit $rc
