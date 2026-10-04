#!/usr/bin/env bash
# One command sets up Claude Code with a vault on a Chromebook (Linux) or any Debian/Ubuntu machine:
#   curl -fsSL https://raw.githubusercontent.com/emilebusiness0/claude-vault-starter/main/bootstrap.sh | bash -s YourName
# It installs the tools, the vault and its rules, connects a private GitHub backup, then opens Claude.
# Safe to run again: everything it does is skipped when already done.
set -euo pipefail
NAME="${1:-}"
REPO="${VAULT_KIT_REPO:-https://github.com/emilebusiness0/claude-vault-starter}"
KIT="$HOME/.vault-kit"
CI="${VAULT_KIT_CI:-}"          # set in automated tests: skips the sign-ins and opening Claude
say() { printf '\n\033[1;32m%s\033[0m\n' "$*"; }
TTY=/dev/tty; [ -r /dev/tty ] && [ -z "$CI" ] || TTY=/dev/null

if [ -z "$NAME" ]; then
  [ -z "$CI" ] && { printf 'Your first name: '; read -r NAME < /dev/tty; }
  NAME="${NAME:-Friend}"
fi

say "Hi $NAME. Setting up Claude with your vault. About 10 minutes; it will ask for two sign-ins."

say "1/6 Installing the basic tools (git, jq, python)..."
sudo apt-get update -qq
sudo apt-get install -y -qq git jq python3 curl ca-certificates gnupg >/dev/null

say "2/6 Installing Node.js 22..."
if ! command -v node >/dev/null || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
  sudo apt-get install -y -qq nodejs >/dev/null
fi
node --version

say "3/6 Installing the GitHub tool..."
if ! command -v gh >/dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq gh >/dev/null
fi
gh --version | head -1

say "4/6 Installing Claude Code..."
export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null; then curl -fsSL https://claude.ai/install.sh | bash; fi
grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
claude --version

say "5/6 Setting up your vault and its rules..."
if [ -d "$KIT/.git" ]; then git -C "$KIT" pull -q --ff-only; else git clone -q "$REPO" "$KIT"; fi
node "$KIT/install.mjs" --name "$NAME"
VAULT="$(node -p 'require(require("os").homedir()+"/.claude/vault-kit.json").vault')"

say "6/6 Backing up your vault to your own private GitHub..."
if [ -n "$CI" ]; then
  echo "(skipped in the automated test)"
elif git -C "$VAULT" remote get-url origin >/dev/null 2>&1; then
  echo "Already backed up to $(git -C "$VAULT" remote get-url origin)"
else
  if ! gh auth status >/dev/null 2>&1; then
    echo "A GitHub page will open. Sign in (or create a free account), type the code shown below, then click Authorize."
    gh auth login --hostname github.com --git-protocol https --web < /dev/tty
  fi
  gh auth setup-git
  LOGIN=$(gh api user --jq .login); ID=$(gh api user --jq .id)
  git -C "$VAULT" config user.email "$ID+$LOGIN@users.noreply.github.com"
  if gh repo view "$LOGIN/vault" >/dev/null 2>&1; then
    git -C "$VAULT" remote add origin "https://github.com/$LOGIN/vault.git"
    echo "A repo called vault already exists on your GitHub; connected to it (nothing was pushed over it)."
  else
    gh repo create vault --private --source "$VAULT" --remote origin --push >/dev/null
    echo "Backed up to https://github.com/$LOGIN/vault (private: only you can see it)."
  fi
fi

say "Done. Opening Claude. The first time, it asks you to sign in with your Claude account."
[ -n "$CI" ] && exit 0
cd "$VAULT"
exec claude "First session on this computer. Read $KIT/SETUP.md and follow it." < /dev/tty
