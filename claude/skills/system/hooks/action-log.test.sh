#!/usr/bin/env bash
# Tests for action-log.   bash action-log.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; HOOK="$HERE/action-log.mjs"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export ACTION_LOG_STATE="$TMP/state"; SID="t"; F="$TMP/state/$SID.actions"
pass=0; fail=0
run() { # tool_name, tool_input json
  jq -cn --arg t "$1" --argjson i "$2" --arg s "$SID" '{session_id:$s,tool_name:$t,tool_input:$i}' | node "$HOOK"; code=$?
}
logged() { [ -s "$F" ] && grep -qF -- "$1" "$F"; }
expect_logged() { rm -rf "$TMP/state"; run "$2" "$3"
  if [ "$code" = 0 ] && logged "$4"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 should be logged"; cat "$F" 2>/dev/null | sed 's/^/    /'; fi; }
expect_quiet() { rm -rf "$TMP/state"; run "$2" "$3"
  if [ "$code" = 0 ] && [ ! -s "$F" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 should NOT be logged"; cat "$F" | sed 's/^/    /'; fi; }

expect_logged "a site deploy" Bash '{"command":"cd duovert-site && npm run deploy"}' "npm run deploy"
expect_logged "wrangler deploy" Bash '{"command":"npx wrangler deploy --env prod"}' "wrangler deploy"
expect_logged "netlify deploy" Bash '{"command":"netlify deploy --prod --dir=dist"}' "netlify deploy"
expect_logged "a git push" Bash '{"command":"git push origin main"}' "git push"
expect_logged "launchctl kickstart" Bash '{"command":"launchctl kickstart -k gui/501/com.example.app"}' "launchctl"
expect_logged "a POST to a real host" Bash '{"command":"curl -s -X POST https://api.example.com/v1/things -d x=1"}' "curl"
expect_logged "an MCP send" mcp__gmail__send_message '{"to":"a@b.c"}' "mcp__gmail__send_message"
expect_logged "an Artifact publish" Artifact '{"action":"publish","file_path":"/tmp/x.html"}' "Artifact"
expect_quiet "an echo that only mentions a deploy" Bash '{"command":"echo \"remember to run npm run deploy later\""}'
expect_quiet "a grep for the command text" Bash '{"command":"grep -rn \"npm run deploy\" notes/"}'
expect_quiet "a heredoc that writes about a deploy" Bash '{"command":"cat > note.md <<'"'"'EOF'"'"'\nwe ran git push and npm run deploy\nEOF"}'
expect_quiet "a commit message that says push" Bash '{"command":"git commit -m \"no more git push here\""}'
expect_logged "a deploy after cd" Bash '{"command":"cd ~/site && npm run deploy"}' "npm run deploy"
expect_logged "a push in another repo with -C" Bash '{"command":"git -C ~/projects/app push origin HEAD"}' "git -C"
expect_logged "npx wrangler with env first" Bash '{"command":"CI=1 npx wrangler deploy"}' "wrangler deploy"
expect_quiet "crontab -l is a read" Bash '{"command":"crontab -l"}'
expect_logged "crontab -r" Bash '{"command":"crontab -r"}' "crontab"
expect_logged "a real deploy AFTER a heredoc" Bash '{"command":"cat > n.md <<'"'"'EOF'"'"'\nabout npm run deploy\nEOF\ncd ~/site && npm run deploy"}' "npm run deploy"
expect_quiet "gh release list is a read" Bash '{"command":"gh release list --limit 1"}'
expect_logged "gh pr merge" Bash '{"command":"gh pr merge 12 --squash"}' "gh pr merge"
expect_quiet "ls" Bash '{"command":"ls -la"}'
expect_quiet "a read-only git question" Bash '{"command":"git merge-base HEAD origin/main"}'
expect_quiet "git status" Bash '{"command":"git status --short"}'
expect_quiet "a vault push (the autocommit's own job)" Bash '{"command":"git -C ~/vault push origin HEAD:refs/heads/main"}'
expect_quiet "a curl GET" Bash '{"command":"curl -s https://duovert.ca/"}'
expect_quiet "a POST to localhost" Bash '{"command":"curl -s -X POST http://127.0.0.1:4820/board -d x=1"}'
expect_quiet "an MCP read" mcp__gmail__search_threads '{"q":"x"}'
expect_quiet "an Artifact read" Artifact '{"action":"read","url":"x"}'
rm -rf "$TMP/state"; echo "not json" | node "$HOOK"; code=$?
if [ "$code" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: bad input must exit 0"; fi
echo "action-log: $pass passed, $fail failed"; [ "$fail" = 0 ]
