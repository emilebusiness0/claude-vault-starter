#!/bin/bash
# PreCompact hook: tells the summary what it must keep.
#
# Each summary is where detail gets lost, so this tells it what to keep.
cat >/dev/null   # the hook input is not needed
cat <<'EOF'
Also keep, in this order and close to word for word:
1. Every request, correction, preference and decision the person made in this conversation, quoted in their own words.
2. The task being worked on right now, and what "done" means for it.
3. Each decision taken and the reason for it, including options that were rejected and why.
4. Every file created, changed or deleted, with its full path and one line on what changed.
5. What was verified and how (the command and what it returned), and what was NOT verified yet.
6. Numbers that were measured, with where they came from.
7. Questions still waiting on the person, and the exact next step.
Drop tool output that was only read to find something. Never write an em dash.
EOF
