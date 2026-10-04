#!/bin/bash
# UserPromptSubmit hook: stamps the start of a new turn and clears the
# previous turn's vault-check decision, so the Stop hook can verify
# whether a save actually happened *this* turn.
INPUT=$(cat)
HERE="$(cd "$(dirname "$0")" && pwd)"
VAULT="${VAULT_DIR:-$(node --input-type=module -e "import {VAULT} from '$HERE/kit.mjs'; console.log(VAULT)" 2>/dev/null)}"
[ -n "$VAULT" ] || VAULT="$HOME/vault"
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
STATE_DIR="$HOME/.claude/state/vault-check"
mkdir -p "$STATE_DIR"
date +%s > "$STATE_DIR/${SESSION_ID}.start"
rm -f "$STATE_DIR/${SESSION_ID}.decision"
# What he typed, so the Stop check (save-check, in the system skill) can ask
# once when he said "from now on" and the session wrote NO_SAVE_NEEDED.
echo "$INPUT" | jq -r '.prompt // ""' | head -c 4000 > "$STATE_DIR/${SESSION_ID}.prompt"

# The canary (2026-09-30). save-check asks every few turns for the last words of one hard rule; a
# session that cannot say them no longer has hard-rules.md in context (a long session, a summary that
# dropped it). It leaves this flag, and the block is re-sent here, once, at his next message.
LOST="$STATE_DIR/${SESSION_ID}.rules-lost"
if [ -f "$LOST" ]; then
  RULES_FILE="${HARD_RULES_FILE:-$HERE/../hard-rules.md}"
  echo "<hard_rules_resent>"
  echo "A check this session showed it no longer had its hard rules in context (rule asked about: $(cat "$LOST")). They are sent again below, word for word, and hold for the rest of the session."
  cat "$RULES_FILE" 2>/dev/null || echo "(hard rules unreadable)"
  echo "</hard_rules_resent>"
  rm -f "$LOST"
fi

# If the autocommit hook could not push, say so out loud. Two copies drifting
# apart in silence is how notes get lost. Reading a flag costs nothing.
FLAG="$STATE_DIR/DIVERGED"
if [ -f "$FLAG" ]; then
  echo "VAULT WARNING: $(cat "$FLAG")"
  echo "The vault is saving on this computer but not reaching GitHub. Fix it before"
  echo "writing more memory: git -C \"$VAULT\" fetch origin, then merge origin/main"
  echo "and read every conflict, assuming the GitHub side may hold real notes this"
  echo "computer does not. Delete $FLAG once the push succeeds."
fi

# Notes nothing links to. The autocommit hook flags them; this says so.
ORPHAN_FLAG="$STATE_DIR/ORPHANS"
if [ -f "$ORPHAN_FLAG" ]; then
  cat "$ORPHAN_FLAG"
  echo "Link each one from README.md, or give it an outbound wikilink, before"
  echo "writing more memory."
fi

# A retraction written as prose, or a malformed row, is never checked.
RETRACTED_FLAG="$STATE_DIR/RETRACTED"
if [ -f "$RETRACTED_FLAG" ]; then
  cat "$RETRACTED_FLAG"
  echo "Add each dead phrase as its own table row in RETRACTED.md before writing"
  echo "more memory. See the 'How to use it' section at the top of that file."
fi

exit 0
