#!/usr/bin/env bash
# Tests for newer-facts.   bash newer-facts.test.sh
# Runs the hook against a throwaway vault. 120 filler notes make word rarity behave as in the real
# vault (a word in two notes out of 120 is rare, a word in all of them is not), with the real thresholds.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/newer-facts.mjs"
V=$(mktemp -d); S=$(mktemp -d); trap 'rm -rf "$V" "$S"' EXIT
V=$(cd "$V" && pwd -P)
export NEWER_FACTS_VAULT="$V" NEWER_FACTS_STATE="$S"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  got: $2"; }
mkdir -p "$V/research" "$V/decisions" "$V/feedback" "$V/filler"
for i in $(seq 1 120); do echo "the quote crm notes number $i about everyday work and the usual things" > "$V/filler/f$i.md"; done
cat > "$V/research/2026-09-24-crm-backup-plan.md" <<'N'
---
name: crm backup plan
---
# Backup plan
The nightly backup copies the database into an iCloud Drive folder called CloudDocs, restored weekly from the snapshot.
N
cat > "$V/research/2026-09-30-later-note.md" <<'N'
# A later note
The nightly backup copies the database into an iCloud Drive folder called CloudDocs, restored weekly from the snapshot.
N
cat > "$V/feedback/undated.md" <<'N'
The nightly backup copies the database into an iCloud Drive folder called CloudDocs, restored weekly from the snapshot.
N
cat > "$V/decisions/lucia.md" <<'N'
| Question | Answer | When | Note |
|---|---|---|---|
| Where does the nightly backup snapshot go? | **Google Drive**, not iCloud Drive, because CloudDocs is full | 2026-09-24 | [[research/2026-09-24-crm-backup-plan]] |
| What colour is the logo? | Emerald on green-black, always | 2026-09-25 | [[duo-vert/brand]] |
| Where is the weekly review done? | Every Sunday, in the notes | 2026-09-22 | [[personal/review]] |
| How is quokka sanctuary ticketing handled? | Turnstile scan at the gate, no paper tickets | 2026-09-25 | [[duo-vert/other]] |
| What things are usual? | Everyday work and the usual things | 2026-09-26 | [[personal/usual]] |
N
cat > "$V/RETRACTED.md" <<'N'
| Dead phrase | What is true now | When | Where |
|---|---|---|---|
| `zebrafish protocol` | Retired for the quokka protocol | 2026-09-27 | [[research/2026-09-24-crm-backup-plan]] |
N
cat > "$V/research/2026-09-20-sanctuary-visit.md" <<'N'
# Sanctuary visit
Notes on the quokka sanctuary: ticketing is by paper ticket at the booth, and the turnstile is unused.
N
run() { # run <session> <file_path> [tool]
  jq -cn --arg s "$1" --arg f "$2" --arg t "${3:-Read}" \
    '{session_id:$s, hook_event_name:"PostToolUse", tool_name:$t, tool_input:{file_path:$f}}' \
    | "$HOOK"; echo "exit=$?"
}

# 1. A dated note, and a newer decision row about the same rare words: one message naming the row.
out=$(run s1 "$V/research/2026-09-24-crm-backup-plan.md")
echo "$out" | grep -q '"additionalContext"' && echo "$out" | grep -q 'decisions/lucia.md' \
  && echo "$out" | grep -q 'Google Drive' && echo "$out" | grep -q 'exit=0' \
  && ok || bad "1 newer row about the same thing is shown" "$out"

# 2. The row's answer is what is shown, and the note is not called wrong.
echo "$out" | grep -q 'newer row wins' && ok || bad "2 says the newer row wins" "$out"

# 3. Same note, same session: silent.
out=$(run s1 "$V/research/2026-09-24-crm-backup-plan.md")
echo "$out" | grep -q 'additionalContext' && bad "3 second read is silent" "$out" || ok

# 4. Another session: told again.
out=$(run s2 "$V/research/2026-09-24-crm-backup-plan.md")
echo "$out" | grep -q 'additionalContext' && ok || bad "4 another session is told" "$out"

# 5. Unrelated rows (logo colour, weekly review) are not shown.
echo "$out" | grep -q 'logo' && bad "5 unrelated row stays out" "$out" || ok

# 6. A row made of common words only is not shown, however many the note shares.
echo "$out" | grep -q 'usual things' && bad "6 common words are not a match" "$out" || ok

# 7. A row that cites this note as its source is shown even with no shared words.
echo "$out" | grep -q 'zebrafish protocol' && ok || bad "7 a row citing the note is shown" "$out"

# 8. A row older than the note is not shown: a note written after the fact already knows it.
cat > "$V/research/2026-09-29-newer-than-rows.md" <<'N'
The nightly backup copies the database into an iCloud Drive folder called CloudDocs, restored weekly from the snapshot.
N
out=$(run s3 "$V/research/2026-09-29-newer-than-rows.md")
echo "$out" | grep -q 'additionalContext' && bad "8 rows older than the note stay out" "$out" || ok

# 9. An undated note (a living note) is silent: it is kept current, only dated notes go stale unseen.
out=$(run s4 "$V/feedback/undated.md")
echo "$out" | grep -q 'additionalContext' && bad "9 living note is silent" "$out" || ok

# 10. Not markdown, or outside the vault: silent, exit 0.
echo x > "$V/research/2026-09-24-a.txt"
out=$(run s5 "$V/research/2026-09-24-a.txt"); echo "$out" | grep -q 'additionalContext' && bad "10a non-md" "$out" || ok
out=$(run s5 /etc/hosts); echo "$out" | grep -q 'additionalContext' && bad "10b outside" "$out" || ok

# 11. Garbage on stdin, or a missing file: exit 0, nothing said, nothing thrown.
out=$(echo 'not json' | "$HOOK"; echo "exit=$?"); [ "$out" = "exit=0" ] && ok || bad "11a garbage input" "$out"
out=$(run s6 "$V/research/2026-09-24-missing.md"); [ "$out" = "exit=0" ] && ok || bad "11b missing file" "$out"

# 12. No RETRACTED.md and no decisions folder: silent, exit 0.
V2=$(mktemp -d); V2=$(cd "$V2" && pwd -P); mkdir -p "$V2/research"; echo "backup notes" > "$V2/research/2026-09-24-x.md"
out=$(NEWER_FACTS_VAULT="$V2" run s7 "$V2/research/2026-09-24-x.md"); [ "$out" = "exit=0" ] && ok || bad "12 empty vault" "$out"; rm -rf "$V2"

# 13. The scan mode prints the same message, for tuning.
out=$("$HOOK" --scan research/2026-09-24-crm-backup-plan.md); echo "$out" | grep -q 'Google Drive' && ok || bad "13 --scan" "$out"

# 14. Word match alone (the row cites some other note): rare shared words bring it in.
out=$(run s8 "$V/research/2026-09-20-sanctuary-visit.md")
echo "$out" | grep -q 'quokka sanctuary ticketing' && ok || bad "14 rare shared words match without a link" "$out"

# 15. ...and the same row does not appear on a note that only shares common words with it.
out=$(run s9 "$V/research/2026-09-24-crm-backup-plan.md")
echo "$out" | grep -q 'quokka sanctuary ticketing' && bad "15 unrelated note stays out" "$out" || ok

echo "newer-facts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
