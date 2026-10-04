#!/usr/bin/env bash
# Tests for retracted-check.   bash retracted-check.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/retracted-check"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MARKER="<!-- retractions above this line were converted to table rows on 2026-09-23 -->"
pass=0; fail=0
expect() { # name, expected exit code, file
  "$CHECK" "$3" > "$TMP/out" 2>&1; code=$?
  if [ "$code" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (exit $code)"; cat "$TMP/out"; fi
}

# A clean file: rows, old prose above the marker, nothing new below.
cat > "$TMP/clean.md" <<EOF
| \`no word cap\` | Under 250 words. | 2026-09-22 | x |
## old section
Dead phrases: "something old that never got a row".
$MARKER
EOF
expect "clean file passes" 0 "$TMP/clean.md"

# The 2026-09-20 row that hid for three days.
cat > "$TMP/half.md" <<EOF
| \`instagram_business_account\` is absent | Same cause. | 2026-09-20 | x |
$MARKER
EOF
expect "row with text outside its quote marks fails" 1 "$TMP/half.md"

# A new prose section appended below the marker, the way 17 were.
cat > "$TMP/prose.md" <<EOF
| \`no word cap\` | Under 250 words. | 2026-09-22 | x |
$MARKER
## 2026-09-24: "something new"
Dead phrases: "something new and wrong", "another wording". Corrected in x.
EOF
expect "new prose retraction without a row fails" 1 "$TMP/prose.md"

# The same prose, once its phrase has a row, is fine: history can stay.
cat > "$TMP/covered.md" <<EOF
| \`no word cap\` | Under 250 words. | 2026-09-22 | x |
| \`something new and wrong\` | The truth. | 2026-09-24 | x |
$MARKER
Dead phrases: "Something new and wrong", "another wording". Corrected in x.
EOF
expect "prose whose first phrase has a row passes" 0 "$TMP/covered.md"

# The bold prose shape used in older sections.
cat > "$TMP/bold.md" <<EOF
$MARKER
Dead phrases, in the words they wore: **"a claim nobody listed"**, **"another"**.
EOF
expect "bold prose shape is caught" 1 "$TMP/bold.md"

# The real file, as converted on 2026-09-23.
expect "the real RETRACTED.md passes" 0 "$HOME/vault/RETRACTED.md"

# A missing file is not a failure of the turn.
expect "missing file exits 0" 0 "$TMP/nope.md"

echo "retracted-check: $pass passed, $fail failed"
[ "$fail" = 0 ]
