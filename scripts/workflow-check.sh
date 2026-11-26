#!/bin/bash
# builder-kit 1.2.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# CI workflow lint (kit 1.2.0, AGENT-ARCHITECTURE.md §1.18): every workflow in .github/workflows must follow the CI rules.
#   scripts/workflow-check.sh [repo dir]      (no network, read-only; exit 0 = holds, 1 = a finding, each printed as FAIL)
# Rules (FAIL): no pull_request_target, workflow_run or issue_comment trigger (read from `on:` in all three forms: scalar, list, map); a top-level `permissions:` with `contents: read` and no
# write at the top; every action pinned to a full commit SHA; every actions/checkout with `persist-credentials: false`;
# no `${{ github.event.* }}` or `${{ github.head_ref }}` inside a `run:` step (pass it through `env:`); a workflow that runs
# on pull_request has `cancel-in-progress: true`. NOTE (not a FAIL): a path filter on a pull_request trigger (a required
# check that a filter skips stays pending: use the always-run docs-only step of §1.18 instead).
# Second narrow escape, workflow_run only (never pull_request_target or issue_comment): a GitHub-hosted workflow that never checks out or runs
# github.event.workflow_run.head_* code carries
#   # workflow-check: allow workflow_run (GitHub-hosted, no checkout or run of github.event.workflow_run.head_* code, <reason>)
# honoured only when the file has no self-hosted runner; printed as a NOTE. The lint cannot check the head_* condition: infra reviews such a workflow by hand.
# One narrow escape: a GitHub-hosted release/deploy job that must push keeps its checkout credentials. The file carries the marker
#   # workflow-check: allow persist-credentials (release, GitHub-hosted, <reason>)
# honoured only when the file has no self-hosted runner; printed as a NOTE. The lint reads workflow text only: it does not judge where
# a job runs, so a project's own runner on its own server is left alone (infra checks that box and its hooks).
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
files = sorted(glob.glob(os.path.join(root, ".github/workflows/*.y*ml")))
for path in files:
    wf = os.path.relpath(path, root)
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    raw_text = "\n".join(lines)
    escape_wr = re.search(r"#\s*workflow-check:\s*allow workflow_run\s*\(GitHub-hosted, no checkout or run of github\.event\.workflow_run\.head_\* code, [^)]+\)", raw_text)
    escape = re.search(r"#\s*workflow-check:\s*allow persist-credentials\s*\(release, GitHub-hosted, [^)]+\)", raw_text)
    code = [re.sub(r"(^|\s)#.*$", "", l) for l in lines]          # comments never count
    text = "\n".join(code)
    def fail(n, msg):
        global bad; bad = True; out.append(f"FAIL {wf}{':%d' % n if n else ''}: {msg}")
    triggers = parse_on(code)
    for bad_t in ("pull_request_target", "workflow_run", "issue_comment"):
        if bad_t == "workflow_run" and bad_t in triggers and escape_wr and not re.search(r"self-hosted", text):
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
                  if escape and not re.search(r"self-hosted", text):
                    out.append(f"NOTE {wf}:{n}: checkout keeps its credentials by the documented release escape (GitHub-hosted release/deploy job that must push)")
                  else:
                    fail(n, "actions/checkout without `persist-credentials: false` (the job token would stay in .git/config)")
        # run steps: no event data in the command text
    k = 0
    while k < len(code):
        m = re.match(r"(\s*)(-\s*)?run\s*:\s*(.*)$", code[k])
        if m:
            col = len(m.group(1)) + (len(m.group(2)) if m.group(2) else 0)
            body, first = [], m.group(3)
            if first[:1] in ("|", ">"):
                j = k + 1
                while j < len(code) and (code[j].strip() == "" or indent(code[j]) > col): body.append((j + 1, code[j])); j += 1
                k = j - 1
            else: body.append((k + 1, first))
            for n, b in body:
                if re.search(r"\$\{\{\s*(github\.event\.|github\.head_ref)", b):
                    fail(n, "event data inside a `run:` step is a script injection: pass it through `env:` and use the variable")
        k += 1
    if "pull_request" in triggers:
        if not re.search(r"cancel-in-progress\s*:\s*(true|\$\{\{)", text):
            fail(0, "runs on pull_request without `concurrency: cancel-in-progress: true` (a superseded run keeps a runner busy)")
        m = re.search(r"^\s*pull_request\s*:\s*\n((?:\s+.*\n?)*)", text, re.M)
        if m and re.search(r"^\s+paths(-ignore)?\s*:", m.group(1).split("\n  push")[0], re.M):
            out.append(f"NOTE {wf}: a path filter on pull_request: a required check it skips stays pending (use the docs-only step, §1.18)")
print("\n".join(out))
sys.exit(1 if bad else 0)
PY
rc=$?
[ $rc = 0 ] && echo "workflow-check: workflows hold"
exit $rc
