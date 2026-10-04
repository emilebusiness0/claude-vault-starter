#!/usr/bin/env bash
# Tests for the hard-rules block that session-start injects (hard-rules.md beside SKILL.md).
# The point: every rule in the block is his words, still in the note it cites. If a note is
# reworded or renamed, this fails and the block is refreshed, instead of quoting a dead sentence.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
VAULT="${HARD_RULES_VAULT:-$(node --input-type=module -e "import {VAULT} from '$HERE/kit.mjs'; console.log(VAULT)")}"
pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); echo "FAIL: $1"; }
check() { if eval "$2"; then ok; else no "$1"; fi; }

out=$(bash "$HERE/session-start")
ctx=$(printf '%s' "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')

check "1 hook output is valid JSON with context" '[ -n "$ctx" ]'
check "2 context holds a hard_rules block" 'printf "%s" "$ctx" | grep -q "<hard_rules>" && printf "%s" "$ctx" | grep -q "</hard_rules>"'
check "3 the other two blocks are still there" 'printf "%s" "$ctx" | grep -q "<session_standard>" && printf "%s" "$ctx" | grep -q "<system_rules>"'
check "4 a known rule reaches the session" 'printf "%s" "$ctx" | grep -qF "Never use em dashes"'
check "5 block is not empty text saying unreadable" '! printf "%s" "$ctx" | grep -q "hard rules unreadable"'

n=$(grep -c '^- ' "$ROOT/hard-rules.md")
check "6 between 25 and 45 rules ($n)" '[ "$n" -ge 25 ] && [ "$n" -le 45 ]'
w=$(wc -w < "$ROOT/hard-rules.md" | tr -d ' ')
check "7 under 1,000 words ($w)" '[ "$w" -lt 1000 ]'
check "8 no em dash in the block" '! grep -q "—" "$ROOT/hard-rules.md"'

res=$(python3 - "$ROOT/hard-rules.md" "$VAULT" <<'PY'
import re,sys
md,vault=sys.argv[1],sys.argv[2]
bad=[]
for l in open(md):
    if not l.startswith("- "): continue
    m=re.match(r'- [^:]+: "(.*)" \[\[([^\]]+)\]\]$',l.rstrip("\n"))
    if not m: bad.append("unparsed: "+l[:50]); continue
    q=m.group(1).replace('\\"','"')
    try: t=open(f"{vault}/{m.group(2)}.md").read()
    except Exception: bad.append("no note: "+m.group(2)); continue
    if q not in t: bad.append("quote gone from "+m.group(2)+": "+q[:50])
print("\n".join(bad) if bad else "OK")
PY
)
check "9 every rule parses, its note exists, its quote is a literal substring: $res" '[ "$res" = OK ]'

# mutation: the check must catch a reworded quote
tmp=$(mktemp -d); cp "$ROOT/hard-rules.md" "$tmp/h.md"
sed -i.bak 's/Never use em dashes/Never ever use em dashes/' "$tmp/h.md"
mres=$(python3 - "$tmp/h.md" "$VAULT" <<'PY'
import re,sys
md,vault=sys.argv[1],sys.argv[2]; bad=0
for l in open(md):
    m=re.match(r'- [^:]+: "(.*)" \[\[([^\]]+)\]\]$',l.rstrip("\n"))
    if m and m.group(1).replace('\\"','"') not in open(f"{vault}/{m.group(2)}.md").read(): bad+=1
print(bad)
PY
)
rm -rf "$tmp"
check "10 a reworded quote is caught (mutation)" '[ "$mres" = 1 ]'

check "11 settings.json runs session-start on startup, clear and compact" 'python3 -c "
import json,os
s=json.load(open(os.path.expanduser(\"~/.claude/settings.json\")))
ok=any(\"session-start\" in h.get(\"command\",\"\") and all(w in g.get(\"matcher\",\"\") for w in (\"startup\",\"clear\",\"compact\")) for g in s[\"hooks\"][\"SessionStart\"] for h in g[\"hooks\"])
raise SystemExit(0 if ok else 1)"'

echo "hard-rules: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
