#!/usr/bin/env bash
# Tests for save-check.   bash save-check.test.sh
# Every case runs the real hook on a throwaway vault, state folder and skills
# folder; the rules it imports come from kit.mjs beside it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/save-check.mjs"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export SAVE_CHECK_STATE="$TMP/state" SAVE_CHECK_VAULT="$TMP/vault" SAVE_CHECK_SKILLS="$TMP/skills"
export SAVE_CHECK_MEMORY="$TMP/MEMORY.md" LUCIA_ROOT="$TMP/lucia"
V="$TMP/vault"; S="$TMP/state"; SID="test-session"
pass=0; fail=0

reset() {
  rm -rf "$TMP/vault" "$TMP/state" "$TMP/skills" "$TMP/MEMORY.md"
  mkdir -p "$V/projects" "$V/decisions" "$V/research/topics" "$V/queue" "$V/reports" "$S" "$TMP/skills/duo-vert"
  cat > "$V/RETRACTED.md" <<'EOF'
# Retracted facts
| Dead phrase | What is true now | When | Where |
|---|---|---|---|
| `an old dead phrase` | The truth. | 2026-09-20 | [[x]] |
EOF
  echo "- [Lucia](x.md) — her notes" > "$TMP/MEMORY.md"
  # The turn started 100 seconds ago, and the prompt Emile typed.
  echo $(( $(date +%s) - 100 )) > "$S/$SID.start"
  echo "ok lets finish it" > "$S/$SID.prompt"
}
decide() { printf '%s\n' "$@" > "$S/$SID.decision"; }
run() { # reply text -> sets $code, $out
  local reply="${1:-Done.}"
  out=$(jq -cn --arg s "$SID" --arg r "$reply" '{session_id:$s,hook_event_name:"Stop",stop_hook_active:false,last_assistant_message:$r}' | node "$HOOK" 2>&1); code=$?
}
expect() { # name, expected code, [text the output must contain]
  if [ "$code" = "$2" ] && { [ -z "${3:-}" ] || grep -qF -- "$3" <<<"$out"; }; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: $1 (exit $code, wanted $2${3:+, containing \"$3\"})"; echo "$out" | sed 's/^/    /' | head -20; fi
}

# ---- the decision itself ----
reset; run
expect "no decision blocks and asks the three questions" 2 "What did the vault say before"
reset; run
expect "the block names the decision file" 2 "$S/$SID.decision"
reset; decide "NO_SAVE_NEEDED"; run
expect "NO_SAVE_NEEDED with no reason blocks" 2 "why"
reset; decide "NO_SAVE_NEEDED: routine question about his schedule"; run
expect "NO_SAVE_NEEDED with a reason passes" 0
reset; decide "whatever"; run
expect "an unreadable decision blocks" 2 "unrecognised"
# 2026-09-29, a real Haiku session: it wrote the REPLACED line alone, three times.
reset; echo x > "$V/decisions/hosting.md"; decide "REPLACED: hosted on wix => Squarespace"; run
expect "REPLACED with no SAVED line says what is missing" 2 "add a SAVED line"
expect "and offers the notes written this turn" 2 "SAVED: $V/decisions/hosting.md"
reset; echo x > "$V/decisions/hosting.md"; decide "**SAVED:** $V/decisions/hosting.md" "- REPLACED: nothing"; run
expect "markdown decoration around the keywords is tolerated" 0
reset; echo x > "$V/decisions/hosting.md"; decide "REPLACED: nothing" "SAVED: $V/decisions/hosting.md"; run
expect "the lines may come in any order" 0

# ---- SAVED must be real ----
reset; echo "x" > "$V/decisions/tech.md"; touch -t 202601010000 "$V/decisions/tech.md"
decide "SAVED: $V/decisions/tech.md" "REPLACED: nothing"; run
expect "a SAVED file not written this turn blocks" 2 "not written this turn"
reset; decide "SAVED: $V/nope.md" "REPLACED: nothing"; run
expect "a SAVED file that does not exist blocks" 2 "not written this turn"
reset; echo "x" > "$V/decisions/tech.md"; decide "SAVED: $V/decisions/tech.md"; run
expect "SAVED without a REPLACED line blocks and asks what it replaced" 2 "REPLACED"
reset; echo "x" > "$V/decisions/tech.md"; decide "SAVED: $V/decisions/tech.md" "REPLACED: nothing"; run
expect "SAVED + REPLACED: nothing passes on a quiet turn" 0
reset; echo "x" > "$V/decisions/tech.md"; decide "SAVED: ~/${V#$HOME/}/decisions/tech.md" "REPLACED: nothing"
[[ "$V" == "$HOME"/* ]] && { run; expect "a ~/ path is understood" 0; } || pass=$((pass+1))

# ---- the Cloudflare miss of 2026-09-28: saved to a log, stale truth elsewhere ----
cloudflare() {
  reset
  echo "**LIVE ON CLOUDFLARE, 2026-09-28 23:11.** duovert.ca publishes with npm run deploy to Cloudflare. The registry switched." > "$V/research/topics/tools-history.md"
  echo '**`master` deploys to duovert.ca on every push, instantly, via Netlify.**' > "$V/projects/site.md"
  printf '| How does duovert.ca get published? | npm run build then netlify deploy --prod | x |\n' > "$V/decisions/duo-vert.md"
  printf 'Never `npm run deploy`. Use `netlify deploy --prod --dir=dist`.\n' > "$TMP/skills/duo-vert/SKILL.md"
  touch -t 202601010000 "$V/projects/site.md" "$V/decisions/duo-vert.md" "$TMP/skills/duo-vert/SKILL.md"
}
cloudflare; decide "SAVED: $V/research/topics/tools-history.md" "REPLACED: nothing"
run "duovert.ca is now live on Cloudflare; the registry switched at 23:10."
expect "REPLACED: nothing after a reply that says something switched asks once" 2 "switched"
run "duovert.ca is now live on Cloudflare; the registry switched at 23:10."
expect "and passes the second time (it asks, it does not nag)" 0

cloudflare; decide "SAVED: $V/research/topics/tools-history.md" "REPLACED: netlify deploy => duovert.ca publishes with npm run deploy to Cloudflare"
run
expect "a replaced phrase still alive in a decisions row blocks" 2 "decisions/duo-vert.md:1"
expect "and names the skill that still says it" 2 "duo-vert/SKILL.md:1"
cloudflare; decide "SAVED: $V/research/topics/tools-history.md" "REPLACED: duovert.ca && via netlify => Cloudflare since 2026-09-28"
run
expect "&& finds two words sharing a line" 2 "projects/site.md:1"
cloudflare; echo 'The CRM, crm.duovert.ca, stays on Netlify.' > "$V/projects/crm.md"; touch -t 202601010000 "$V/projects/crm.md"
printf '~~master deploys on push~~\n' > "$V/projects/site.md"
decide "SAVED: $V/research/topics/tools-history.md" "REPLACED: duovert.ca && netlify => Cloudflare"; run
expect "in a && pair, duovert.ca does not match crm.duovert.ca" 2 "decisions/duo-vert.md:1"
grep -q "projects/crm.md" <<<"$out"; code=$([ $? = 0 ] && echo 1 || echo 0); expect "and the CRM line is not listed" 0
cloudflare; decide "SAVED: $V/research/topics/tools-history.md" "REPLACED: duovert.ca && cloudflare pages => x"
run
expect "&& with one word missing from every line finds nothing" 0

# fixed properly: a history note, a struck line, a line saying "superseded"
cloudflare
printf '| How does duovert.ca get published? | npm run deploy, Cloudflare | x |\n' > "$V/decisions/duo-vert.md"
printf -- '- (superseded 2026-09-28) it used `netlify deploy --prod --dir=dist`.\n' > "$TMP/skills/duo-vert/SKILL.md"
printf 'netlify deploy was the way until 2026-09-28\n' > "$V/research/topics/tools-history.md"
printf '~~master deploys on push via netlify deploy~~\n' > "$V/projects/site.md"
printf 'we ran netlify deploy at 21:00\n' > "$V/reports/2026-09-28-night.md"
printf 'netlify deploy\n' > "$V/queue/STATUS.md"
printf -- '---\nkind: history\n---\nnetlify deploy --prod was the command\n' > "$V/decisions/duo-vert-history.md"
decide "SAVED: $V/decisions/duo-vert.md" "REPLACED: netlify deploy => duovert.ca publishes with npm run deploy to Cloudflare"
run
expect "marked lines, history notes, reports and queue files are not hits" 0
grep -qF '| `netlify deploy` | duovert.ca publishes with npm run deploy to Cloudflare |' "$V/RETRACTED.md"
code=$?; out=$(tail -2 "$V/RETRACTED.md"); expect "the replaced phrase becomes a RETRACTED row the morning audit hunts" 0
grep -qF '[[decisions/duo-vert]]' "$V/RETRACTED.md"; code=$?; expect "the row links the note that holds the truth" 0
python3 "$HERE/retracted-check" "$V/RETRACTED.md" >/dev/null 2>&1; code=$?; out=""
expect "the row it writes passes retracted-check" 0
run; n=$(grep -c '`netlify deploy`' "$V/RETRACTED.md")
[ "$n" = 1 ]; code=$?; out="rows: $n"; expect "a second pass does not duplicate the row" 0
cloudflare; decide "SAVED: $V/research/topics/tools-history.md" "REPLACED: duovert.ca && via netlify => x"
printf '~~master deploys on push~~\n' > "$V/projects/site.md"; run
grep -q 'duovert.ca && via netlify' "$V/RETRACTED.md"; [ $? != 0 ]; code=$?; out=""
expect "a && pair is hunted now but never written as a row (the audit reads plain phrases)" 0

# the memory index loaded into every session is hunted too
reset; echo "deploys with npm run deploy" > "$V/decisions/tech.md"
echo "- [Website](w.md) — duovert.ca deploys to Netlify on push" >> "$TMP/MEMORY.md"
decide "SAVED: $V/decisions/tech.md" "REPLACED: deploys to netlify on push => npm run deploy"; run
expect "a stale line in MEMORY.md is a hit" 2 "MEMORY.md:2"

# the global CLAUDE.md, read before every session, is hunted too
reset; mkdir -p "$TMP/home/.claude"; echo "publish with netlify deploy" > "$TMP/home/.claude/CLAUDE.md"
echo x > "$V/decisions/tech.md"; decide "SAVED: $V/decisions/tech.md" "REPLACED: netlify deploy => x"; HOME="$TMP/home" run
expect "a stale line in the global CLAUDE.md is a hit" 2 "CLAUDE.md:1"

# ---- phrases that cannot work ----
reset; echo x > "$V/decisions/tech.md"; decide "SAVED: $V/decisions/tech.md" 'REPLACED: `npm` => x'; run
expect "a phrase with a backtick is refused (it could never be a RETRACTED row)" 2 "backtick"
reset; echo x > "$V/decisions/tech.md"; decide "SAVED: $V/decisions/tech.md" "REPLACED: ab => x"; run
expect "a phrase too short to mean anything is refused" 2 "too short"
reset; echo x > "$V/decisions/tech.md"; decide "SAVED: $V/decisions/tech.md" "REPLACED: netlify deploy"; run
expect "REPLACED without => says what is true now" 2 "=>"

# ---- NO_SAVE after a change ----
reset; decide "NO_SAVE_NEEDED: nothing new"; run "I switched the site to Cloudflare and it is live."
expect "NO_SAVE_NEEDED after a reply saying something switched asks once" 2 "switched"
run "I switched the site to Cloudflare and it is live."
expect "and then accepts his answer" 0
reset; echo "from now on quotes include travel" > "$S/$SID.prompt"; decide "NO_SAVE_NEEDED: nothing durable"; run "Noted."
expect "a prompt saying 'from now on' makes NO_SAVE_NEEDED ask once" 2 "from now on"

# ---- it never loops forever and never takes a turn down ----
reset; for i in 1 2 3; do run; done
expect "the third block is the last" 2
run; expect "after three blocks in one turn it lets the turn end" 0 "gave up"
reset; for i in 1 2 3; do run; done; decide "NO_SAVE_NEEDED: a routine question"; run
expect "a right answer on the fourth stop passes normally" 0
grep -q "gave up" <<<"$out"; code=$?; expect "without the gave-up message" 1
rm -f "$S/$SID.decision"; echo $(( $(date +%s) - 5 )) > "$S/$SID.start"; run
expect "a new turn starts a new count" 2
out=$(echo "not json" | node "$HOOK" 2>&1); code=$?
expect "bad input never blocks" 0
out=$(jq -cn '{session_id:"x",stop_hook_active:true}' | SAVE_CHECK_AUDIT=/nope.js node "$HOOK" 2>&1); code=$?
expect "stop_hook_active no longer waves a turn through" 2



# ---- answering in the reply: one model call instead of a tool call and a wrap-up ----
reset; run; expect "first stop with no decision blocks" 2 "Reply with"
run "NO_SAVE_NEEDED: routine question about his schedule"
expect "after a block, the decision in the reply is read (no file needed)" 0
reset; echo x > "$V/decisions/hosting.md"; run
run "$(printf 'SAVED: %s/decisions/hosting.md\nREPLACED: nothing' "$V")"
expect "SAVED and REPLACED in the reply pass" 0
reset; echo x > "$V/decisions/hosting.md"; echo x > "$V/decisions/other.md"; run
run "$(printf 'SAVED: %s/decisions/hosting.md, %s/decisions/other.md\nREPLACED: nothing' "$V" "$V")"
expect "a comma-separated SAVED list is read (trailing commas are not part of the path)" 0
reset; echo "the site is on Squarespace" > "$V/decisions/hosting.md"; echo "the site is hosted on wix now" > "$V/projects/web.md"; run
run "$(printf '**SAVED:** %s/decisions/hosting.md\n- REPLACED: hosted on wix => Squarespace' "$V")"
expect "a reply's REPLACED line runs the same search" 2 "projects/web.md"
reset; run "NO_SAVE_NEEDED: routine question about his schedule"
expect "a decision in the FIRST stop's reply is not taken, that is just his answer" 2
reset; run; run "Here is my answer, the format is SAVED: /x or NO_SAVE_NEEDED: why, as asked."
expect "prose that merely mentions the format is not a decision" 2
# the second ask in a session is short
reset; run; SHORT_SID=$SID
rm -f "$S/$SID.decision"; echo $(( $(date +%s) - 5 )) > "$S/$SID.start"; run
expect "a later ask in the same session is the short one" 2 "Same three questions"
[ ${#out} -lt 900 ]; code=$?; out=""; expect "and it is short" 0

# ---- the action net: what the turn DID (deploys, pushes, sends), logged by action-log ----
act() { printf '%s\t%s\t%s\n' "${2:-$(date +%s)}" "Bash" "$1" >> "$S/$SID.actions"; }
reset; act "cd duovert-site && npm run deploy"; run
expect "the first question lists what the turn ran" 2 "npm run deploy"
reset; act "npm run deploy"; decide "NO_SAVE_NEEDED: routine question"; run
expect "a bare nothing-to-save is refused once when the turn deployed" 2 "npm run deploy"
run
expect "asked once, so the second stop passes" 0
reset; echo x > "$V/decisions/hosting.md"; act "wrangler deploy"; decide "SAVED: $V/decisions/hosting.md" "REPLACED: nothing"; run
expect "REPLACED nothing after a deploy is asked once" 2 "wrangler deploy"
run
expect "and passes on the second stop" 0
reset; act "npm run deploy" $(( $(date +%s) - 500 )); decide "NO_SAVE_NEEDED: routine question"; run
expect "an action from before this turn started is not counted" 0
reset; echo "hosted on Cloudflare" > "$V/decisions/hosting.md"; act "npm run deploy"; decide "SAVED: $V/decisions/hosting.md" "REPLACED: hosted on wix => Cloudflare"; run
expect "naming a real replaced fact needs no extra ask" 0

# ---- short on screen (2026-09-29, Emile: the reply was too long) ----
reset; echo x > "$V/decisions/hosting.md"; echo y > "$V/projects/site.md"
decide "SAVED: decisions/hosting.md projects/site.md" "REPLACED: nothing"; run
expect "vault-relative paths are accepted, two in a row stay two" 0 "Vault: 2 saved, 0 replaced."
reset; mkdir -p "$V/.claude/hooks"; echo x > "$V/.claude/hooks/save-check"; echo y > "$V/.claude/hooks/save-check.test.sh"
decide "SAVED: .claude/hooks/save-check .claude/hooks/save-check.test.sh" "REPLACED: nothing"; run
expect "relative paths that are not .md files stay separate" 0 "Vault: 2 saved"
reset; echo x > "$V/decisions/hosting.md"; echo y > "$V/projects/site.md"; decide "SAVED: auto" "REPLACED: nothing"; run
expect "SAVED: auto counts the files written this turn" 0 "Vault: 2 saved"
reset; decide "SAVED: auto" "REPLACED: nothing"; run
expect "SAVED: auto with nothing written blocks" 2 "found nothing"
reset; echo x > "$V/decisions/hosting.md"; decide "SAVED: decisions/nope.md" "REPLACED: nothing"; run
expect "a relative path that does not exist still blocks" 2 "decisions/nope.md"
reset; echo "hosted on Cloudflare" > "$V/decisions/hosting.md"; decide "SAVED: decisions/hosting.md" "REPLACED: hosted on wix => Cloudflare"; run
expect "the pass line is a count, not a paragraph" 0 "Vault: 1 saved, 1 replaced"
reset; run
expect "the ask tells the session not to recap" 2 "no recap"

# ---- re-read after saving (2026-09-30): the saved note must say the new fact ----
reset; echo "The notes for the garden, nothing about hosting at all." > "$V/decisions/hosting.md"
decide "SAVED: $V/decisions/hosting.md" "REPLACED: hosted on wix => Cloudflare Pages since Monday"; run
expect "a saved note that does not say the new fact is sent back once" 2 "read back from disk"
expect "and the ask names the words it could not find" 2 '"cloudflare"'
run
expect "and the second stop passes (paraphrase is allowed, the ask is once per turn)" 0
reset; echo "Hosting moved to Cloudflare Pages on Monday." > "$V/decisions/hosting.md"
decide "SAVED: $V/decisions/hosting.md" "REPLACED: hosted on wix => Cloudflare Pages since Monday"; run
expect "a saved note that says the fact passes at once" 0 "Vault: 1 saved, 1 replaced"
reset; echo "Hosting moved to Cloudflare Pages." > "$V/decisions/hosting.md"
decide "SAVED: $V/decisions/hosting.md" "REPLACED: hosted on wix => Cloudflare Pages since Monday"; run
expect "a paraphrase with a third or more of the words still passes" 0
reset; echo "a note" > "$V/decisions/hosting.md"; echo "Cloudflare Pages Monday" > "$V/decisions/other.md"
decide "SAVED: $V/decisions/hosting.md $V/decisions/other.md" "REPLACED: hosted on wix => Cloudflare Pages since Monday"; run
expect "the fact may be in any of the saved notes" 0

# ---- it logs every decision, for the board ----
reset; decide "NO_SAVE_NEEDED: routine"; run
grep -q "$SID" "$S/save-check.log"; code=$?; out=""; expect "each stop is one log line" 0
# 2026-09-29: probe sessions on a throwaway vault wrote into the real log and
# turned Lucia's board line amber. The real state folder with any other vault
# logs to its own file. HOME is a scratch one here, so nothing real is touched.
reset; decide "NO_SAVE_NEEDED: routine question"; mkdir -p "$TMP/home/.claude/state/vault-check"
cp "$S/$SID.start" "$S/$SID.decision" "$TMP/home/.claude/state/vault-check/"
out=$(jq -cn --arg s "$SID" '{session_id:$s}' | env -u SAVE_CHECK_STATE HOME="$TMP/home" node "$HOOK" 2>&1); code=$?
expect "a probe on another vault passes as usual" 0
[ -s "$TMP/home/.claude/state/vault-check/save-check.other-vault.log" ] && [ ! -e "$TMP/home/.claude/state/vault-check/save-check.log" ]; code=$?; out=""
expect "and logs to its own file, never the board's" 0

# ---- the canary: a third line on some asks, scored, a miss repaired at the next message ----
cat > "$TMP/hard-rules.md" <<'RULESEOF'
Hard rules.

- Alpha: "Always check the thing before you send the final reply." [[feedback/a]]
- Beta: "Never put the secret token into any vault file ever." [[feedback/b]]
- Gamma: "Kill the process by its port and never by pattern." [[feedback/c]]
RULESEOF
export SAVE_CHECK_HARD_RULES="$TMP/hard-rules.md"
canary_words() { case "$1" in Alpha) echo "the final reply";; Beta) echo "vault file ever";; Gamma) echo "never by pattern";; esac; }
canary_label() { grep -o 'labelled "[^"]*"' <<<"$out" | head -1 | sed 's/labelled "//; s/"//'; }
next_turn() { echo $(( $(date +%s) - 50 + ${1:-0} )) > "$S/$SID.start"; rm -f "$S/$SID.decision" "$S/$SID.turn.json"; }
yes() { code=$1; out=""; }   # a plain shell check turned into an expect: yes $? then expect name 0
reset; run
expect "the first ask of a session carries the usual questions" 2 "What did the vault say before"
grep -q "RULES:" <<<"$out"; yes $(( $? == 0 ? 1 : 0 )); expect "and no canary line" 0
next_turn 1; run
expect "the second ask carries the canary line" 2 'RULES: <the last four words of the hard rule labelled'
label=$(canary_label); words=$(canary_words "$label")
[ -n "$words" ]; yes $?; expect "and names one of the rules by label ($label)" 0
decide "NO_SAVE_NEEDED: routine question" "RULES: $words"; run
expect "a right canary answer passes" 0
grep -q "ok	$label" "$S/canary.log"; yes $?; expect "and is logged ok" 0
[ ! -e "$S/$SID.rules-lost" ]; yes $?; expect "and raises no flag" 0
# a session that lost the block: wrong words, then no line at all
reset; run; next_turn 1; run; label=$(canary_label)
decide "NO_SAVE_NEEDED: routine question" "RULES: something entirely made up"; run
expect "a wrong canary answer still passes the turn, it never blocks" 0
grep -q "wrong	$label" "$S/canary.log"; yes $?; expect "and is logged wrong" 0
[ -s "$S/$SID.rules-lost" ]; yes $?; expect "and raises the rules-lost flag, so the block is re-sent" 0
reset; run; next_turn 1; run; label=$(canary_label)
decide "NO_SAVE_NEEDED: routine question"; run
expect "no canary line at all passes too" 0
grep -q "unanswered	$label" "$S/canary.log" && [ -s "$S/$SID.rules-lost" ]; yes $?; expect "and counts as a miss" 0
# the answer can come in the reply to the block, like the rest of the decision
reset; run; next_turn 1; run; label=$(canary_label); words=$(canary_words "$label")
run "NO_SAVE_NEEDED: routine question
RULES: $words"
expect "a canary line in the reply to the block is read" 0
grep -q "ok	$label" "$S/canary.log"; yes $?; expect "and scored" 0
# the same turn asking again keeps the same canary
reset; run; next_turn 1; run; l1=$(canary_label); run; l2=$(canary_label)
[ -n "$l1" ] && [ "$l1" = "$l2" ]; yes $?; expect "a re-ask inside one turn keeps the same rule" 0
# asks 2 and 6 carry it, the others do not
reset; hits=""
for i in 1 2 3 4 5 6 7 8 9; do next_turn "$i"; run; grep -q 'RULES: <the last' <<<"$out" && hits="$hits$i"; done
[ "$hits" = "26" ]; yes $?; expect "canary on asks 2 and 6 of nine (got: $hits)" 0
# no hard-rules file: no canary, nothing breaks
reset; export SAVE_CHECK_HARD_RULES="$TMP/none.md"; run; next_turn 1; run
expect "no rules file: the ask is the usual short one" 2 "Same three questions"
grep -q 'RULES: <the last' <<<"$out"; yes $(( $? == 0 ? 1 : 0 )); expect "and carries no canary" 0
export SAVE_CHECK_HARD_RULES="$TMP/hard-rules.md"

echo "save-check: $pass passed, $fail failed"
[ "$fail" = 0 ]
