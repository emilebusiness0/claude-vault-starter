#!/usr/bin/env bash
# Tests for the canary re-send in vault-turn-start.sh.   bash vault-turn-start.test.sh
# Runs the hook with a scratch HOME, so nothing real is read or cleared.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/vault-turn-start.sh"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
export HOME="$D/home"; S="$HOME/.claude/state/vault-check"; mkdir -p "$S"
echo "- Alpha: \"Always check the thing before you send the final reply.\" [[feedback/a]]" > "$D/hard-rules.md"
export HARD_RULES_FILE="$D/hard-rules.md"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  got: $2"; }
run() { jq -cn --arg s "$1" '{session_id:$s,prompt:"hello"}' | bash "$HOOK"; }

out=$(run sess1)
grep -q "hard_rules_resent" <<<"$out" && bad "1 no flag, nothing re-sent" "$out" || ok

echo "Alpha" > "$S/sess1.rules-lost"
out=$(run sess1)
grep -q "<hard_rules_resent>" <<<"$out" && grep -q "send the final reply" <<<"$out" && ok || bad "2 flag re-sends the rules word for word" "$out"
grep -q "rule asked about: Alpha" <<<"$out" && ok || bad "3 says which rule the check asked about" "$out"
[ ! -e "$S/sess1.rules-lost" ] && ok || bad "4 the flag is cleared, so it is sent once"
out=$(run sess1)
grep -q "hard_rules_resent" <<<"$out" && bad "5 not sent a second time" "$out" || ok

echo "Alpha" > "$S/other.rules-lost"
out=$(run sess2)
grep -q "hard_rules_resent" <<<"$out" && bad "6 another session's flag is not mine" "$out" || ok
[ -e "$S/other.rules-lost" ] && ok || bad "7 and is left for that session"

echo "Alpha" > "$S/sess3.rules-lost"; out=$(HARD_RULES_FILE="$D/missing.md" run sess3)
grep -q "hard rules unreadable" <<<"$out" && ok || bad "8 a missing rules file says so instead of failing" "$out"

echo "vault-turn-start: $pass passed, $fail failed"
[ "$fail" = 0 ]
