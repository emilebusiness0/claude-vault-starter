#!/bin/bash
# Stop hook: commits any vault changes made this turn, and pushes when the
# push is a clean fast-forward.
#
# Why this exists: writing a note and backing it up are two separate acts,
# and only the first happens on its own. In the system this kit comes from,
# the vault once sat uncommitted for 16 days and lost a to-do item when two
# copies drifted apart. So every turn commits, and the push is automatic.
#
# Design rules, in priority order:
#   1. Never block or fail a turn. Always exit 0.
#   2. Never touch the network in the foreground. Push is backgrounded.
#   3. Never commit on top of an in-progress merge/rebase/bisect.
#   4. If the push cannot fast-forward, leave a flag so the next turn says so
#      out loud rather than letting the divergence grow silently again.

HERE="$(cd "$(dirname "$0")" && pwd)"
VAULT="${VAULT_DIR:-$(node --input-type=module -e "import {VAULT} from '$HERE/kit.mjs'; console.log(VAULT)" 2>/dev/null)}"
[ -n "$VAULT" ] || VAULT="$HOME/vault"
STATE_DIR="$HOME/.claude/state/vault-check"
FLAG="$STATE_DIR/DIVERGED"
LOG="$STATE_DIR/autocommit.log"

mkdir -p "$STATE_DIR"

# Rule 1: nothing below is allowed to take the turn down with it.
{
  [ -d "$VAULT/.git" ] || exit 0
  cd "$VAULT" || exit 0

  # Rule 3: a half-finished merge is a human's problem, not a hook's.
  #
  # Use only markers git actually removes when the operation finishes. An
  # earlier version of this hook checked REBASE_HEAD, which git leaves behind
  # after a *successful* rebase: this vault had one sitting there from
  # 2026-08-12, so the hook silently skipped every turn from the moment it was
  # installed. Failing safe is still failing. The in-progress signal for a
  # rebase is the directory, never the file.
  GITDIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
  if [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
    echo "$(date -Iseconds) skipped: rebase in progress" >> "$LOG"
    exit 0
  fi
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_START; do
    if [ -e "$GITDIR/$marker" ]; then
      echo "$(date -Iseconds) skipped: $marker present" >> "$LOG"
      exit 0
    fi
  done

  # Keep the graph connected. Every vault note must be reachable in Obsidian's
  # graph view, meaning something links to it or it links out.
  #
  # A note nothing links to is written once and never found again, so this
  # lives in a hook, not a prose rule. Tests: graph-repair.test.sh beside it.
  #
  # Reports are repaired automatically because the fix is deterministic (an
  # Index line below the title). Anything else is flagged, never guessed at.
  ORPHAN_FLAG="$STATE_DIR/ORPHANS"
  GREPAIR="$HERE/graph-repair"
  if [ -x "$GREPAIR" ]; then
    "$GREPAIR" "$VAULT" > "$ORPHAN_FLAG.tmp" 2>/dev/null
    grep '^repaired ' "$ORPHAN_FLAG.tmp" | while IFS= read -r l; do
      echo "$(date -Iseconds) graph: ${l}" >> "$LOG"
    done
    grep '^orphan ' "$ORPHAN_FLAG.tmp" | sed 's/^orphan /  /' > "$ORPHAN_FLAG.list"
  else
    : > "$ORPHAN_FLAG.list"
  fi
  if [ -s "$ORPHAN_FLAG.list" ]; then
    { echo "vault: these notes float alone in graph view (no link in or out), as of $(date -Iseconds):"
      cat "$ORPHAN_FLAG.list"; } > "$ORPHAN_FLAG"
    echo "$(date -Iseconds) orphans flagged: $(wc -l < "$ORPHAN_FLAG.list" | tr -d ' ')" >> "$LOG"
  else
    rm -f "$ORPHAN_FLAG"
  fi
  rm -f "$ORPHAN_FLAG.tmp" "$ORPHAN_FLAG.list"

  # Retractions written as prose are never checked, so they are flagged.
  RETRACTED_FLAG="$STATE_DIR/RETRACTED"
  RCHECK="$HERE/retracted-check"
  if [ -x "$RCHECK" ] && ! "$RCHECK" "$VAULT/RETRACTED.md" > "$RETRACTED_FLAG.tmp" 2>/dev/null; then
    { echo "vault: RETRACTED.md has entries the morning audit cannot read, as of $(date -Iseconds):"
      sed 's/^/  /' "$RETRACTED_FLAG.tmp"; } > "$RETRACTED_FLAG"
    echo "$(date -Iseconds) retracted-check flagged: $(wc -l < "$RETRACTED_FLAG.tmp" | tr -d ' ')" >> "$LOG"
  else
    rm -f "$RETRACTED_FLAG"
  fi
  rm -f "$RETRACTED_FLAG.tmp"

  # Nothing staged, unstaged or untracked means nothing to do.
  if [ -z "$(git status --porcelain)" ]; then
    exit 0
  fi

  COUNT=$(git status --porcelain | wc -l | tr -d ' ')
  FILES=$(git status --porcelain | awk '{print $NF}' | head -5 | tr '\n' ' ')

  git add -A || exit 0
  git commit -q -F - <<EOF || exit 0
Vault autosave: $COUNT file(s)

$FILES

Committed automatically at the end of a Claude Code turn so vault writes
always have history and a restore point. Reword or squash freely.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF

  echo "$(date -Iseconds) committed $COUNT file(s)" >> "$LOG"

  # Rule 2 + 4: push out of band, and record it when it will not go cleanly.
  # No GitHub backup set up yet: committing locally is all there is to do.
  git remote get-url origin >/dev/null 2>&1 || exit 0
  (
    if git push --quiet origin HEAD 2>>"$LOG"; then
      rm -f "$FLAG"
      echo "$(date -Iseconds) pushed" >> "$LOG"
    else
      echo "vault: this computer and the GitHub copy have drifted apart; push refused $(date -Iseconds)" > "$FLAG"
      echo "$(date -Iseconds) push refused, flag set" >> "$LOG"
    fi
  ) >/dev/null 2>&1 &

  exit 0
} >/dev/null 2>&1

exit 0
