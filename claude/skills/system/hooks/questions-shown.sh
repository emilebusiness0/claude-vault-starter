#!/bin/bash
# Stop hook: a final reply that asks for answers to questions "above" must have
# shown those questions somewhere in the conversation.
#
# Why this exists: a session once ended with "your answers to the 7 questions
# above" when no message had ever shown them; they lived only in a file.
#
# How it decides: the last reply mentions questions (or answers) "above",
# "ci-dessus", "plus haut" and so on; then the conversation's visible replies
# must contain at least two list lines ending in a question mark, or an
# AskUserQuestion call. If not, the stop is blocked with the reason, once
# (stop_hook_active prevents a loop). Fails open on anything unexpected.
INPUT=$(cat)
command -v python3 >/dev/null || exit 0
printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
except Exception:
    sys.exit(0)
if d.get("stop_hook_active"):
    sys.exit(0)
path = d.get("transcript_path") or ""
texts, asked = [], False
try:
    with open(path, errors="ignore") as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("isSidechain") or e.get("type") != "assistant":
                continue
            for x in (e.get("message") or {}).get("content") or []:
                if not isinstance(x, dict):
                    continue
                if x.get("type") == "text" and (x.get("text") or "").strip():
                    texts.append(x["text"])
                elif x.get("type") == "tool_use" and x.get("name") == "AskUserQuestion":
                    asked = True
except Exception:
    sys.exit(0)
if not texts:
    sys.exit(0)
last = texts[-1]
# Quoted text is a phrase being talked about, not a request to him. On
# 2026-09-28 the reply describing this very hook ("answer the questions above",
# in quotes) was blocked by it.
last = re.sub(r"`[^`\n]*`|\u201c[^\u201d\n]*\u201d|\"[^\"\n]*\"|\u00ab[^\u00bb\n]*\u00bb", " ", last)
POINTS = re.compile(r"\b(questions?|r[ée]ponses?|answers?)\b[^.\n]{0,60}?\b(above|ci-dessus|au-dessus|plus haut|listed earlier|from earlier|earlier in this chat)\b", re.I)
if not POINTS.search(last):
    sys.exit(0)
QLINE = re.compile(r"^\s*(\d+[.)]|[-*•])\s+.*\?\s*(\*\*)?\s*$", re.M)
shown = sum(len(QLINE.findall(t)) for t in texts)
if asked or shown >= 2:
    sys.exit(0)
print(json.dumps({"decision": "block", "reason": "Your reply asks for answers to questions above, but no reply in this conversation shows them as a list (and no AskUserQuestion was used). Paste the questions into the reply, numbered, before stopping."}))
'
exit 0
