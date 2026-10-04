#!/usr/bin/env bash
# Tests for note-size.   bash note-size.test.sh
# Runs the hook against a throwaway vault with the real audit module, so the
# size rule tested is the one the morning audit applies.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/note-size.mjs"
V=$(mktemp -d); S=$(mktemp -d); trap 'rm -rf "$V" "$S"' EXIT
V=$(cd "$V" && pwd -P)
export NOTE_SIZE_VAULT="$V" NOTE_SIZE_STATE="$S"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  got: $2"; }
words() { python3 -c "print(' '.join(['word'] * $1))"; }
note() { # note <path> <words> [kind]
  mkdir -p "$(dirname "$V/$1")"
  { echo "---"; echo "name: t"; [ -n "${3:-}" ] && echo "  kind: $3"; echo "---"; echo; words "$2"; } > "$V/$1"
}
run() { # run <session> <file_path> [tool]
  jq -cn --arg s "$1" --arg f "$2" --arg t "${3:-Edit}" \
    '{session_id:$s, hook_event_name:"PostToolUse", tool_name:$t, tool_input:{file_path:$f}}' \
    | "$HOOK"; echo "exit=$?"
}

# 1. A current note over 3,000 words gets one message naming it and its history note.
note duo-vert/big.md 3100
out=$(run s1 "$V/duo-vert/big.md")
echo "$out" | grep -q '"additionalContext"' && echo "$out" | grep -q 'duo-vert/big.md' \
  && echo "$out" | grep -q 'duo-vert/big-history.md' && echo "$out" | grep -q 'exit=0' \
  && ok || bad "1 oversized current note is flagged" "$out"

# 2. The same note, same session: silent (once per note per session).
out=$(run s1 "$V/duo-vert/big.md")
echo "$out" | grep -q 'additionalContext' && bad "2 second edit is silent" "$out" || ok

# 3. The same note in another session: flagged again.
out=$(run s2 "$V/duo-vert/big.md" Write)
echo "$out" | grep -q 'additionalContext' && ok || bad "3 another session is told" "$out"

# 4. Under the ceiling: silent.
note personal/small.md 2900
out=$(run s1 "$V/personal/small.md")
echo "$out" | grep -q 'additionalContext' && bad "4 small note is silent" "$out" || ok

# 5. A history note, by name or by property: silent.
note personal/thing-history.md 9000
note personal/record.md 9000 history
out=$(run s1 "$V/personal/thing-history.md"; run s1 "$V/personal/record.md")
echo "$out" | grep -q 'additionalContext' && bad "5 history notes are silent" "$out" || ok

# 6. Machine files (reports, queue, dated research) and non-markdown: silent.
note reports/2026-09-28-numbers.md 9000
note queue/worklist.md 9000
note research/2026-09-28-long.md 9000
mkdir -p "$V/duo-vert"; words 9000 > "$V/duo-vert/data.txt"
out=$(for f in reports/2026-09-28-numbers.md queue/worklist.md research/2026-09-28-long.md duo-vert/data.txt; do run s1 "$V/$f"; done)
echo "$out" | grep -q 'additionalContext' && bad "6 machine files are silent" "$out" || ok

# 7. A file outside the vault: silent.
O=$(mktemp -d); mkdir -p "$O/duo-vert"; words 9000 > "$O/duo-vert/big.md"
out=$(run s1 "$O/duo-vert/big.md"); rm -rf "$O"
echo "$out" | grep -q 'additionalContext' && bad "7 outside the vault is silent" "$out" || ok

# 8. Garbage input, a missing file, a missing audit module: silent, exit 0.
out=$(echo 'not json' | "$HOOK"; echo "exit=$?")
{ echo "$out" | grep -q 'exit=0' && ! echo "$out" | grep -q 'additionalContext'; } && ok || bad "8a garbage input" "$out"
out=$(run s1 "$V/duo-vert/gone.md")
{ echo "$out" | grep -q 'exit=0' && ! echo "$out" | grep -q 'additionalContext'; } && ok || bad "8b missing file" "$out"
out=$(NOTE_SIZE_AUDIT=/nonexistent/vault-audit.js run s3 "$V/duo-vert/big.md")
{ echo "$out" | grep -q 'exit=0' && ! echo "$out" | grep -q 'additionalContext'; } && ok || bad "8c missing audit module" "$out"

# 9. The message is valid hook JSON and has no em dash.
out=$(run s4 "$V/duo-vert/big.md" | sed -n 1p)
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 && ok || bad "9a valid JSON" "$out"
echo "$out" | grep -q $'\xe2\x80\x94' && bad "9b no em dash" "$out" || ok

echo "note-size: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
