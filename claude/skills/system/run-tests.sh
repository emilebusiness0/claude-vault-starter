#!/usr/bin/env bash
# Runs every hook test and prints one total. Exit 0 only when all pass.
# Tests use throwaway folders; they never touch the real vault.
cd "$(dirname "$0")/hooks" || exit 1
pass=0; fail=0; bad=()
for t in *.test.sh; do
  line=$(bash "$t" 2>&1 | grep -E '[0-9]+ passed, [0-9]+ failed' | tail -1)
  p=$(grep -oE '[0-9]+ passed' <<<"$line" | grep -oE '[0-9]+'); f=$(grep -oE '[0-9]+ failed' <<<"$line" | grep -oE '[0-9]+')
  [ -z "$line" ] && { f=1; p=0; }
  pass=$((pass + ${p:-0})); fail=$((fail + ${f:-0}))
  [ "${f:-0}" -gt 0 ] && bad+=("${t%.test.sh}")
  printf '%-18s %s\n' "${t%.test.sh}" "${line:-NO RESULT LINE (crashed)}"
done
echo "TOTAL: $pass passed, $fail failed${bad:+ (in: ${bad[*]})}"
[ "$fail" -eq 0 ]
