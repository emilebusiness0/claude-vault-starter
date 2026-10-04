# claude-vault-starter

Sets up Claude Code with a personal notebook (a "vault" of plain text notes) and a set of rules that run on every session: Claude saves what you tell it, checks the right notes before acting, and asks before it sends, buys or deletes anything. The notebook is backed up to your own private GitHub.

## Install (Chromebook, Debian or Ubuntu)

1. On a Chromebook, turn on Linux first: Settings, About ChromeOS, Developers, Linux development environment, Turn on. Then open the Terminal app.
2. Paste this, replacing `YourName`, and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/emilebusiness0/claude-vault-starter/main/bootstrap.sh | bash -s YourName
```

It asks for your Linux password once if it needs one, then two sign-ins: GitHub (for the backup) and Claude (a Pro plan or higher). Then the Claude desktop app opens (official Linux beta): sign in, click the Code tab, pick the `vault` folder and say hi. Claude takes it from there: a quick self-check, then about 50 questions so it knows who you are.

To open Claude later: open the Claude app from the app launcher, click the Code tab and pick the `vault` folder (or type `claude` in a Terminal). The website version at claude.ai/code is a different thing that asks for a GitHub repo; you never need it.

## What it installs

- `~/vault`: the notebook. `README.md` is its index, `DECISIONS.md` holds settled questions, `feedback/` holds how you want Claude to work, `personal/about-me.md` holds who you are.
- `~/.claude/CLAUDE.md`: loads the notebook's index into every session.
- `~/.claude/settings.json`: the hooks. They make Claude save after each turn (or say why nothing needed saving), check the relevant rule notes before sending or deciding, keep notes short and current, and commit the notebook to git after every change.
- `~/.vault-kit`: this repo. Run `bash ~/.vault-kit/bootstrap.sh YourName` again any time to update the hooks; your notes are never overwritten.

Nothing personal is in this repo. Your notes live only on your computer and in your private GitHub repo called `vault`.

## Tests

`bash ~/.claude/skills/system/run-tests.sh` runs every hook test in throwaway folders. Every push runs the full install and the tests on Ubuntu and on Debian 12.
