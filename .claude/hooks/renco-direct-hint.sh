#!/bin/bash
# builder-kit 1.4.0: a kit file. Never edit it here; a change goes to infra, which ships a new kit version.
# UserPromptSubmit hint (infra-control#317, infra verdict on templates#194): the hook input carries the submitted text
# (`prompt`) but no origin, so a person's prompt cannot be proven. What can be done: recognise the KNOWN injected forms
# and, for every other prompt, add ONE line of context reminding the builder of the "Renco direct" rule. It only
# reminds: it never blocks, never sets the label, never writes anything, exits 0, is bounded. A forged form (text that
# imitates an injected one) only silences the reminder; a plain prompt from a session may trigger it. Both are harmless.
# Forms that keep it silent (exactly what the case statement below implements): a path under /Users/Shared/infra-naar-
# (infra brief) anywhere in the prompt; the tags <cross-session-message, <task-notification, <system-reminder anywhere;
# <<autonomous-loop (loop sentinel) anywhere; a prompt that STARTS with "[scheduled", "Scheduled task", "build issue #"
# or "/" (slash command).
# Known limits: the hook input is read up to 1 MB (1.2.1; larger input = silent), then only the first 4000 characters of the prompt are looked at; a marker inside text the person pasted
# (<pasted_content ...> lines) also silences it, because the match is on the whole prompt text.
in="$(head -c 1048576)" || exit 0                    # 1 MB cap (1.2.1): a long prompt used to cut the JSON and silence the hint
prompt="$(printf '%s' "$in" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("prompt","")[:4000])
except Exception: pass' 2>/dev/null)" || exit 0
[ -n "$prompt" ] || exit 0
case "$prompt" in
  *"/Users/Shared/infra-naar-"*|*"<cross-session-message"*|*"<task-notification"*|*"<system-reminder"*|\
  *"<<autonomous-loop"*|"[scheduled"*|"Scheduled task"*|"build issue #"*|"/"*) exit 0 ;;
esac
msg="If this is Renco's decision or task, given to you directly: write the 'Renco direct' line (Renco direct YYYY-MM-DD HH:MM: <decision>) in its issue or PR and put the label renco-direct on it (scripts/renco-direct-label.sh creates it). Ignore this for a brief, another session's message or your own idea."
python3 -I -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":sys.argv[1]}}))' "$msg" 2>/dev/null
exit 0
