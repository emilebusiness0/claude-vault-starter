# First session on a new computer

This file is for Claude. The person just ran the one-line installer and Claude opened for the first time. Do these steps in order, in plain everyday words, with no jargon. Their name is in `~/.claude/vault-kit.json` (`name`), and so is the vault folder (`vault`).

## 1. Say hi in three lines

Say who you are and what was just set up, in about this spirit: a private notebook (the vault) where everything they tell you is saved and kept for next time, a set of rules that make you check before sending, buying or deleting anything, and a backup of the notebook to their own private GitHub. Then say the plan for today: a quick check, then about 50 questions so you actually know who they are.

## 2. Check the install yourself

Run `bash ~/.claude/skills/system/run-tests.sh`. Report the TOTAL line only. If anything failed, say what in one line, read the failing test, and fix it before going on (the kit lives in `~/.vault-kit`; the installed copy is in the vault under `.claude/skills/system`). Never tell them it worked if the TOTAL line shows a failure.

Also check, without asking them anything:
- `git -C <vault> remote get-url origin` prints a GitHub address. If not, the backup step was skipped: run `gh auth status`, and if they are signed in, run `gh repo create vault --private --source <vault> --remote origin --push`. If they are not signed in, walk them through `gh auth login --web` with numbered steps.
- `git -C <vault> config user.email` is set. If not, set it to their GitHub noreply address (`<id>+<login>@users.noreply.github.com` from `gh api user`).

## 3. Tell them how to use it from now on

Three short lines:
- To open Claude later: open the Terminal app, type `claude`, press Enter. The notebook and the rules load on their own every time.
- On the phone or in a browser (claude.ai or the Claude app), the chat does not see the notebook. Big things happen here; quick questions can happen there.
- Say "remember this" any time, and it goes in the notebook. They can also just talk: you save what matters on your own.

## 4. Run the interview

Open `.claude/INTERVIEW.md` in the vault and follow it from section 1. It saves after every section, so stopping halfway is fine; say that once at the start. If `.claude/interview-progress.md` already exists, resume where it stopped.

## 5. At the end of today

Say in two lines what you now know and what is still missing, and that the next session picks up from here. Do not leave the about-me note saying the interview has not been done unless sections are still missing.
