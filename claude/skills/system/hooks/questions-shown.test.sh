#!/bin/bash
# Tests for questions-shown.sh. Run: bash ~/.claude/hooks/questions-shown.test.sh
H="$(cd "$(dirname "$0")" && pwd)/questions-shown.sh"
T=$(mktemp -d)
pass=0; fail=0
me() { python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$1"; }
ask() { echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{}}]}}'; }
run() { printf '{"transcript_path":"%s","stop_hook_active":%s}' "$1" "${2:-false}" | bash "$H"; }
blocks() { run "$@" | grep -c '"decision": "block"'; }
check() { if [ "$2" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $3: got $2, wanted $1"; fi; }

# The real 2026-09-23 shape: a plan mentions the questions, the list is never shown.
{ me "Plan: I will ask you 7 questions about weeds, one at a time."; me "The article is built. Send me your answers to the 7 questions above and I will finish it."; } > "$T/a.jsonl"
check 1 "$(blocks "$T/a.jsonl")" "answers to questions above that were never shown are blocked"

{ me $'Here are the questions:\n1. What weeds do you see most?\n2. Do you use polymeric sand?\n3. How often do clients call back?'; me "Send me your answers to the questions above."; } > "$T/b.jsonl"
check 0 "$(blocks "$T/b.jsonl")" "questions shown as a numbered list pass"

{ me $'Two things only you know:\n- Is the quote free?\n- Do you serve Aylmer?'; me "Réponds aux questions ci-dessus quand tu peux."; } > "$T/c.jsonl"
check 0 "$(blocks "$T/c.jsonl")" "a bullet list in French passes"

{ ask; me "Thanks, once you answer the questions above I will continue."; } > "$T/d.jsonl"
check 0 "$(blocks "$T/d.jsonl")" "questions asked through AskUserQuestion pass"

{ me "Done. The page is live and verified on the phone."; } > "$T/e.jsonl"
check 0 "$(blocks "$T/e.jsonl")" "a reply that points to no questions is never judged"

{ me 'Fix 8: no "answer the questions above" unless they were shown. It also ignores `the questions above` in code.'; } > "$T/f.jsonl"
check 0 "$(blocks "$T/f.jsonl")" "the phrase quoted while talking about it is not a request (false alarm of 2026-09-28)"

check 0 "$(blocks "$T/a.jsonl" true)" "a second stop in a row is let through (no loop)"
check 0 "$(echo 'garbage' | bash "$H" | grep -c block)" "bad input fails open"
check 0 "$(blocks "$T/missing.jsonl")" "a missing transcript fails open"
rm -rf "$T"
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
