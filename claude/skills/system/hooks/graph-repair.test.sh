#!/usr/bin/env bash
# Tests for graph-repair.   bash graph-repair.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPAIR="$HERE/graph-repair"
V=$(mktemp -d); trap 'rm -rf "$V"' EXIT
pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "$2"; }
has()  { grep -qF -- "$2" "$V/$1"; }
line() { sed -n "${2}p" "$V/$1"; }
run()  { "$REPAIR" "$V" > "$V.out" 2>&1; }

mkdir -p "$V/reports" "$V/personal" "$V/Excalidraw" "$V/research"
echo "# Home" > "$V/README.md"
printf -- "---\nname: standing\n---\n\n# Standing orders\n\n[[README]]\n" > "$V/personal/standing-orders.md"

# 1. The exact shape the old hook left on 2026-09-15, 09-21 and 09-28.
cat > "$V/reports/2026-09-28-numbers.md" <<'EOF'
---

*Index: [[README]] · context: [[personal/standing-orders]], [[queue/backlog]]*

name: 2026-09-28-numbers
description: "Duo Vert search week."
metadata:
  type: project
---

# Numbers, week of 2026-09-28

*Measured by Lucia's Analyst.*

```
Clicks 11, was 10.
```
EOF

# 2. A report with properties and no link at all: the stamp must go below the title.
cat > "$V/reports/2026-09-29-numbers.md" <<'EOF'
---
name: 2026-09-29-numbers
---

# Numbers, week of 2026-09-29

```
Clicks 12.
```
EOF

# 3. A report with no properties, title on line 1 (the old hook's only safe case).
printf "# Morning 2026-09-30\n\nNothing linked here.\n" > "$V/reports/2026-09-30-morning.md"

# 4. A knowledge note with no links: flagged, never touched.
printf -- "---\nname: lonely\n---\n\n# Lonely\n\nNo links.\n" > "$V/personal/lonely.md"
cp "$V/personal/lonely.md" "$V/lonely.before"

# 5. Links only inside code do not count.
printf "# Code only\n\n\`[[README]]\`\n\n\`\`\`\n[[README]]\n\`\`\`\n" > "$V/personal/code-only.md"

# 6. A quoted property link counts, for both ends.
printf -- "---\nname: follow-up\nbuilds_on: \"[[research/base]]\"\n---\n\n# Follow-up\n" > "$V/research/follow-up.md"
printf -- "---\nname: base\n---\n\n# Base\n" > "$V/research/base.md"

# 7. Alias and heading links count as inbound.
printf "# Alias\n\n[[personal/aliased|a nicer name]] and [[personal/headed#Part]]\n" > "$V/personal/alias-source.md"
printf "# Aliased\n" > "$V/personal/aliased.md"
printf "# Headed\n" > "$V/personal/headed.md"

# 8. A markdown link counts; a link to a missing note does not.
printf "# Md\n\n[text](../personal/md-target.md)\n" > "$V/personal/md-source.md"
printf "# Md target\n" > "$V/personal/md-target.md"
printf "# Dangling\n\n[[personal/does-not-exist]]\n" > "$V/personal/dangling.md"

# 9. Drawings are exempt.
printf -- "---\nexcalidraw-plugin: parsed\n---\n" > "$V/Excalidraw/drawing.excalidraw.md"

run
out=$(cat "$V.out")

# 1: moved out of the properties block, below the title, properties intact.
f=reports/2026-09-28-numbers.md
[ "$(line $f 2)" = "name: 2026-09-28-numbers" ] && ok || bad "1: properties must start with name: after the fix" "$(head -4 $V/$f)"
awk 'NR>1 && /^---$/{exit} NR>1 && /Index:/{found=1} END{exit found}' "$V/$f" && ok || bad "1: Index line still inside the properties block"
grep -n "Index:" "$V/$f" | grep -q "^1[0-9]:\|^[0-9]:" && [ "$(grep -n '^# Numbers' "$V/$f" | cut -d: -f1)" -lt "$(grep -n 'Index:' "$V/$f" | cut -d: -f1)" ] && ok || bad "1: Index line must sit below the title" "$(cat $V/$f)"
echo "$out" | grep -qx "repaired $f" && ok || bad "1: repair must be reported" "$out"
echo "$out" | grep -q "orphan $f" && bad "1: must not still be an orphan" "$out" || ok

# 2: stamped below the title, not in the properties.
f=reports/2026-09-29-numbers.md
[ "$(line $f 2)" = "name: 2026-09-29-numbers" ] && ok || bad "2: properties untouched"
[ "$(grep -n '^# Numbers' "$V/$f" | cut -d: -f1)" -lt "$(grep -n 'Index:' "$V/$f" | cut -d: -f1)" ] && ok || bad "2: stamp below the title" "$(cat $V/$f)"

# 3: title on line 1 keeps working.
f=reports/2026-09-30-morning.md
[ "$(line $f 1)" = "# Morning 2026-09-30" ] && [ "$(line $f 3 | cut -c1-8)" = "*Index: " ] && ok || bad "3: stamp under a line-1 title" "$(cat $V/$f)"

# 4: flagged and untouched.
echo "$out" | grep -qx "orphan personal/lonely.md" && ok || bad "4: knowledge orphan must be flagged" "$out"
cmp -s "$V/personal/lonely.md" "$V/lonely.before" && ok || bad "4: a knowledge orphan must never be edited"

# 5: code does not link.
echo "$out" | grep -qx "orphan personal/code-only.md" && ok || bad "5: links in code must not count" "$out"

# 6: property links count both ways.
echo "$out" | grep -q "research/follow-up.md\|research/base.md" && bad "6: quoted property link must count" "$out" || ok

# 7: alias and heading.
echo "$out" | grep -q "personal/aliased.md\|personal/headed.md" && bad "7: alias/heading links must count as inbound" "$out" || ok

# 8: md link counts, dangling does not.
echo "$out" | grep -q "personal/md-target.md" && bad "8: markdown link must count" "$out" || ok
echo "$out" | grep -qx "orphan personal/dangling.md" && ok || bad "8: a link to a missing note must not count" "$out"

# 9: drawings exempt.
echo "$out" | grep -q "Excalidraw" && bad "9: drawings are exempt" "$out" || ok

# 10: idempotent, second run changes nothing.
tar -C "$V" -cf "$V.a.tar" . 2>/dev/null; run; tar -C "$V" -cf "$V.b.tar" . 2>/dev/null
( cd "$V" && find . -type f -name '*.md' -exec cksum {} + | sort ) > "$V.sum2"
run
( cd "$V" && find . -type f -name '*.md' -exec cksum {} + | sort ) > "$V.sum3"
cmp -s "$V.sum2" "$V.sum3" && ok || bad "10: a second run must change nothing"
grep -q "^repaired" "$V.out" && bad "10: nothing left to repair on the second run" "$(cat $V.out)" || ok
rm -f "$V.a.tar" "$V.b.tar" "$V.sum2" "$V.sum3" "$V.out"

echo "graph-repair: $pass passed, $fail failed"
[ "$fail" = 0 ]
