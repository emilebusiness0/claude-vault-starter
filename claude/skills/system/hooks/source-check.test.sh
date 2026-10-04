#!/usr/bin/env bash
# Tests for source-check.   bash source-check.test.sh
# Runs the hook against a throwaway rules file, transcript and state folder.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/source-check.mjs"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
export SOURCE_CHECK_STATE="$D/state" SOURCE_CHECK_RULES="$D/rules.md"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  got: $2"; }
cat > "$D/rules.md" <<'R'
Test hard rules.

- Sending: "Every message is shown as a draft first." [[feedback/telegram-group-send-freely]]
- Accounts: "Read freely, draft freely, send never." [[feedback/account-access-via-tokens]]
- Email drafts: "Emails go as plain text, never in a code block" [[feedback/show-email-drafts-in-chat]]
- Dashes: "Never use em dashes" [[feedback/no-em-dashes]]
- Legal: "Never edit the wording of legal pages" [[feedback/legal-content-needs-permission]]
- Money: "not fund or activate anything that costs money" [[feedback/no-paid-setup-before-ready-to-use]]
- Decisions: "Real decisions wait." [[feedback/plain-language-and-everyday-decisions]]
R
: > "$D/empty.jsonl"
tool_use() { # tool_use <file> <name> <json input>
  jq -cn --arg n "$2" --argjson i "$3" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:$i}]}}' >> "$1"
}
call() { # call <session> <transcript> <tool> <json input>
  jq -cn --arg s "$1" --arg t "$2" --arg n "$3" --argjson i "$4" \
    '{session_id:$s, hook_event_name:"PreToolUse", transcript_path:$t, tool_name:$n, tool_input:$i}' | node "$HOOK"
}
denied() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }

# 1 a plain command is never touched
out=$(call s1 "$D/empty.jsonl" Bash '{"command":"ls -la"}')
[ -z "$out" ] && ok || bad "1 ls is silent" "$out"

# 2 a telegram send with nothing opened is denied, with quotes and paths
out=$(call s2 "$D/empty.jsonl" Bash '{"command":"curl -s https://api.telegram.org/botX/sendMessage -d text=hi"}')
if denied "$out" && printf '%s' "$out" | grep -q 'feedback/telegram-group-send-freely.md' && printf '%s' "$out" | grep -q 'shown as a draft first'; then ok; else bad "2 telegram denied with quote and note" "$out"; fi

# 3 picks exactly two rules
n=$(printf '%s' "$out" | grep -o 'open [a-z/-]*\.md' | wc -l | tr -d ' ')
[ "$n" = "2" ] && ok || bad "3 two rules named (got $n)" "$out"

# 4 after the session opened both notes the same call passes
T="$D/t4.jsonl"
tool_use "$T" Read '{"file_path":"/Users/x/Documents/emile-secondbrain/feedback/telegram-group-send-freely.md"}'
tool_use "$T" Read '{"file_path":"/Users/x/Documents/emile-secondbrain/feedback/account-access-via-tokens.md"}'
out=$(call s4 "$T" Bash '{"command":"curl -s https://api.telegram.org/botX/sendMessage -d text=hi"}')
[ -z "$out" ] && ok || bad "4 opened notes pass" "$out"

# 5 chat text that merely names the note is not opening it
T="$D/t5.jsonl"
jq -cn '{type:"assistant",message:{content:[{type:"text",text:"I will read feedback/telegram-group-send-freely.md and feedback/account-access-via-tokens.md"}]}}' >> "$T"
out=$(call s5 "$T" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}')
denied "$out" && ok || bad "5 chat text is not opening a note" "$out"

# 6 the memory folder's flat name counts as opening it
T="$D/t6.jsonl"
tool_use "$T" Read '{"file_path":"/Users/x/.claude/projects/p/memory/feedback_telegram_group_send_freely.md"}'
tool_use "$T" Read '{"file_path":"/Users/x/.claude/projects/p/memory/feedback_account_access_via_tokens.md"}'
out=$(call s6 "$T" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}')
[ -z "$out" ] && ok || bad "6 flat memory name counts" "$out"

# 7 a shell cat of the note counts
T="$D/t7.jsonl"
tool_use "$T" Bash '{"command":"cat ~/vault/feedback/telegram-group-send-freely.md feedback/account-access-via-tokens.md"}'
out=$(call s7 "$T" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}')
[ -z "$out" ] && ok || bad "7 cat of both notes counts" "$out"

# 7b a Write or heredoc that only contains the note names is not opening them
T="$D/t7b.jsonl"
tool_use "$T" Write '{"file_path":"/x/test.sh","content":"feedback/telegram-group-send-freely.md feedback/account-access-via-tokens.md"}'
tool_use "$T" Bash '{"command":"cat > t.sh <<EOF\nfeedback/telegram-group-send-freely.md feedback/account-access-via-tokens.md\nEOF"}'
out=$(call s7b "$T" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}')
denied "$out" && ok || bad "7b writing the note names is not reading the notes" "$out"

# 8 denial budget: denied twice, the third try goes through
call s8 "$D/empty.jsonl" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}' >/dev/null
call s8 "$D/empty.jsonl" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}' >/dev/null
out=$(call s8 "$D/empty.jsonl" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}')
[ -z "$out" ] && ok || bad "8 third try passes" "$out"
grep -q '"why":"denial budget spent"' "$D/state/log.jsonl" && ok || bad "8b skip is logged"

# 9 an em dash in the text of a send brings the Dashes rule in
out=$(call s9 "$D/empty.jsonl" mcp__gmail__create_draft '{"body":"Hello — thanks"}')
printf '%s' "$out" | grep -q 'feedback/no-em-dashes.md' && ok || bad "9 em dash picks Dashes" "$out"

# 10 a mail tool is a send; a session-messaging tool is not
out=$(call s10 "$D/empty.jsonl" mcp__abc__send_message '{"to":"a@b.ca"}'); denied "$out" && ok || bad "10 gmail send_message is a send" "$out"
out=$(call s10b "$D/empty.jsonl" mcp__ccd_session_mgmt__send_message '{"x":1}'); [ -z "$out" ] && ok || bad "10b ccd send_message is not" "$out"

# 11 a real publish is gated, a read of an artifact is not
out=$(call s11 "$D/empty.jsonl" Artifact '{"file_path":"/x/a.html","icon":"chart"}'); denied "$out" && ok || bad "11 artifact publish gated" "$out"
out=$(call s11b "$D/empty.jsonl" Artifact '{"action":"read","url":"u"}'); [ -z "$out" ] && ok || bad "11b artifact read not gated" "$out"

# 12 deploy and push are publishes
out=$(call s12 "$D/empty.jsonl" Bash '{"command":"cd site && npm run deploy"}'); denied "$out" && printf '%s' "$out" | grep -q 'legal-content-needs-permission' && ok || bad "12 deploy picks Legal" "$out"

# 12b words that only mention a deploy or a send are not one
out=$(call s12b "$D/empty.jsonl" Bash '{"command":"echo \"npm run deploy\" > notes.txt"}'); [ -z "$out" ] && ok || bad "12b echo of a deploy command is not one" "$out"
out=$(call s12c "$D/empty.jsonl" Bash '{"command":"python3 - <<EOF\nprint(\"git push and npm run deploy\")\nEOF"}'); [ -z "$out" ] && ok || bad "12c heredoc text is not a command" "$out"
out=$(call s12d "$D/empty.jsonl" Bash '{"command":"git push origin main"}'); denied "$out" && ok || bad "12d a real git push is gated" "$out"
out=$(call s12e "$D/empty.jsonl" Bash '{"command":"npm test && npm run deploy"}'); denied "$out" && ok || bad "12e a deploy after && is gated" "$out"
out=$(call s12f "$D/empty.jsonl" Bash '{"command":"cat > t.sh <<EOF\ncurl https://api.telegram.org/botX/sendMessage\nEOF"}'); [ -z "$out" ] && ok || bad "12f a telegram url inside a heredoc is not a send" "$out"

# 12g pushing the vault's own repo is not publishing (2026-09-30), but any other push, or a mix, still is
out=$(call s12g "$D/empty.jsonl" Bash '{"command":"cd ~/vault && git merge --no-edit origin/main && git push -q origin main"}'); [ -z "$out" ] && ok || bad "12g cd to the vault then push passes" "$out"
out=$(call s12h "$D/empty.jsonl" Bash "$(jq -cn --arg c "git -C $HOME/vault push origin main" '{command:$c}')"); [ -z "$out" ] && ok || bad "12h git -C the vault push passes" "$out"
out=$(jq -cn --arg c "$HOME/vault/queue" '{session_id:"s12i",hook_event_name:"PreToolUse",transcript_path:"'"$D"'/empty.jsonl",cwd:$c,tool_name:"Bash",tool_input:{command:"git push origin main"}}' | node "$HOOK"); [ -z "$out" ] && ok || bad "12i a push from inside the vault passes" "$out"
out=$(jq -cn '{session_id:"s12j",hook_event_name:"PreToolUse",transcript_path:"'"$D"'/empty.jsonl",cwd:"/Users/x/Documents/site",tool_name:"Bash",tool_input:{command:"git push origin main"}}' | node "$HOOK"); denied "$out" && ok || bad "12j a push from another folder is gated" "$out"
out=$(call s12k "$D/empty.jsonl" Bash '{"command":"cd ~/vault && git push -q && cd ~/Documents/site && npm run deploy"}'); denied "$out" && ok || bad "12k a vault push chained with a deploy is gated" "$out"
out=$(call s12l "$D/empty.jsonl" Bash '{"command":"cd ~/vault && git push -q; cd ~/projects/app && git push"}'); denied "$out" && ok || bad "12l a vault push and another repo's push is gated" "$out"
out=$(call s12m "$D/empty.jsonl" Bash '{"command":"cd ~/Documents/site && git push"}'); denied "$out" && ok || bad "12m another repo's push is gated" "$out"

# 13 a price file edit is gated, a vault edit is not
out=$(call s13 "$D/empty.jsonl" Edit '{"file_path":"/Users/x/Documents/site/soumission.html"}'); denied "$out" && printf '%s' "$out" | grep -q 'no-paid-setup' && ok || bad "13 price edit picks Money" "$out"
out=$(call s13b "$D/empty.jsonl" Edit "$(jq -cn --arg p "$HOME/vault/decisions/duo-vert.md" '{file_path:$p}')"); [ -z "$out" ] && ok || bad "13b vault edit not gated" "$out"

# 14 legal file edit
out=$(call s14 "$D/empty.jsonl" Write '{"file_path":"/Users/x/site/conditions-contrat.html"}'); denied "$out" && printf '%s' "$out" | grep -q 'legal-content-needs-permission' && ok || bad "14 legal edit gated" "$out"

# 15 fail open: no transcript, unreadable transcript, garbage input, missing rules file
out=$(jq -cn '{session_id:"s15",tool_name:"Bash",tool_input:{command:"curl https://api.telegram.org/botX/sendMessage"}}' | node "$HOOK"); [ -z "$out" ] && ok || bad "15a no transcript passes" "$out"
out=$(call s15b "$D/does-not-exist.jsonl" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}'); [ -z "$out" ] && ok || bad "15b unreadable transcript passes" "$out"
out=$(printf 'not json' | node "$HOOK"); rc=$?; { [ -z "$out" ] && [ "$rc" = 0 ]; } && ok || bad "15c garbage passes" "$out"
out=$(SOURCE_CHECK_RULES="$D/none.md" call s15d "$D/empty.jsonl" Bash '{"command":"curl https://api.telegram.org/botX/sendMessage"}'); [ -z "$out" ] && ok || bad "15d missing rules file passes" "$out"

# 16 against the real hard-rules.md: every label the hook names exists, and every note it points to exists
REAL="$HERE/../hard-rules.md"; VAULT="${SOURCE_CHECK_VAULT:-$HOME/vault}"
labels=$(grep -o '\["[A-Z][^]]*\]' "$HERE/source-check".mjs | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//' | sort -u)
miss=""
while IFS= read -r l; do [ -z "$l" ] && continue; grep -q "^- $l: " "$REAL" || miss="$miss [$l]"; done <<< "$labels"
[ -z "$miss" ] && ok || bad "16 labels named in source-check are all in hard-rules.md" "$miss"
gone=""
while IFS= read -r n; do [ -f "$VAULT/$n.md" ] || gone="$gone $n"; done < <(grep -o '\[\[[^]]*\]\]' "$REAL" | tr -d '[]' | sort -u)
[ -z "$gone" ] && ok || bad "16b every note behind a hard rule exists" "$gone"

echo "source-check: $pass passed, $fail failed"
[ "$fail" = 0 ]
