#!/usr/bin/env node
// Installs the vault kit for one person: the vault, the system skill and its hooks, the global rules.
// Safe to run again: it never overwrites a note or a rule file that already exists, only the hook code.
// Usage: node install.mjs --name "Beckett" [--vault ~/vault]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const KIT = import.meta.dirname;
const HOME = os.homedir();
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > -1 ? process.argv[i + 1] : d; };
const NAME = arg("name");
if (!NAME) { console.error('usage: node install.mjs --name "First name" [--vault ~/vault]'); process.exit(1); }
const VAULT = path.resolve(String(arg("vault", path.join(HOME, "vault"))).replace(/^~(?=\/|$)/, HOME));
const CLAUDE = path.join(HOME, ".claude");
const SKILL = path.join(VAULT, ".claude", "skills", "system");
const d = new Date();
const DATE = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const render = t => t.replaceAll("{{NAME}}", NAME).replaceAll("{{VAULT}}", VAULT).replaceAll("{{DATE}}", DATE);
const TEXT = /\.(md|mjs|js|sh|json|txt|py)$|^[^.]+$|^\.gitignore$/;
const done = [];

// Copy a tree. Kit-owned code (hooks) is refreshed; anything a person or a session may have edited is kept.
function copyTree(src, dst, { refresh = () => false } = {}) {
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), t = path.join(dst, e.name);
    if (e.isDirectory()) { fs.mkdirSync(t, { recursive: true }); copyTree(s, t, { refresh }); continue; }
    if (fs.existsSync(t) && !refresh(s)) continue;
    const buf = fs.readFileSync(s);
    fs.writeFileSync(t, TEXT.test(e.name) ? render(buf.toString("utf8")) : buf);
    fs.chmodSync(t, fs.statSync(s).mode & 0o777);
    done.push(t);
  }
}

// 1. The vault and its .claude folder (interview, skill, hooks).
fs.mkdirSync(VAULT, { recursive: true });
copyTree(path.join(KIT, "vault"), VAULT);
fs.mkdirSync(SKILL, { recursive: true });
copyTree(path.join(KIT, "claude", "skills", "system"), SKILL, { refresh: s => s.includes(`${path.sep}hooks${path.sep}`) || s.endsWith(".mjs") });
for (const f of fs.readdirSync(path.join(SKILL, "hooks"))) fs.chmodSync(path.join(SKILL, "hooks", f), 0o755);

// 2. Where everything is, for the hooks.
fs.mkdirSync(CLAUDE, { recursive: true });
fs.writeFileSync(path.join(CLAUDE, "vault-kit.json"), JSON.stringify({ name: NAME, vault: VAULT, memory: path.join(CLAUDE, "CLAUDE.md") }, null, 2) + "\n");

// 3. The skill where Claude Code looks for it.
const link = path.join(CLAUDE, "skills", "system");
fs.mkdirSync(path.dirname(link), { recursive: true });
try { fs.lstatSync(link); } catch { fs.symlinkSync(SKILL, link); done.push(link); }

// 4. The global rules file, which loads the vault index into every session.
const MARK = "<!-- vault-kit -->";
const claudeMd = path.join(CLAUDE, "CLAUDE.md");
const ours = `${MARK}\n${render(fs.readFileSync(path.join(KIT, "claude", "CLAUDE.md"), "utf8"))}`;
const existing = fs.existsSync(claudeMd) ? fs.readFileSync(claudeMd, "utf8") : "";
if (!existing.includes(MARK)) { fs.writeFileSync(claudeMd, existing ? `${existing.trimEnd()}\n\n${ours}` : ours); done.push(claudeMd); }

// 5. The hooks, merged into settings.json. Earlier entries from this kit are replaced, everything else is kept.
const H = path.join(SKILL, "hooks");
const q = p => `"${p}"`;
const node = f => ({ type: "command", command: `node ${q(path.join(H, f))}` });
const sh = f => ({ type: "command", command: `bash ${q(path.join(H, f))}` });
const ourHooks = {
  SessionStart: [{ matcher: "startup|clear|compact", hooks: [sh("session-start")] }],
  PreCompact: [{ hooks: [sh("precompact-keep.sh")] }],
  UserPromptSubmit: [{ hooks: [sh("vault-turn-start.sh")] }],
  Stop: [{ hooks: [sh("vault-autocommit.sh"), { ...node("save-check.mjs"), timeout: 20 }, sh("questions-shown.sh")] }],
  PreToolUse: [{ matcher: "Bash|Artifact|mcp__.*|Write|Edit|MultiEdit", hooks: [{ ...node("source-check.mjs"), timeout: 10 }] }],
  PostToolUse: [
    { matcher: "Edit|Write|MultiEdit", hooks: [{ ...node("note-size.mjs"), timeout: 10 }] },
    { matcher: "Bash|Artifact|mcp__.*", hooks: [{ ...node("action-log.mjs"), timeout: 5 }] },
    { matcher: "Read", hooks: [{ ...node("newer-facts.mjs"), timeout: 10 }] },
  ],
};
const settingsFile = path.join(CLAUDE, "settings.json");
let settings = {};
try { settings = JSON.parse(fs.readFileSync(settingsFile, "utf8")); } catch {}
if (fs.existsSync(settingsFile)) fs.copyFileSync(settingsFile, `${settingsFile}.bak-${DATE}`);
settings.hooks ||= {};
for (const [event, groups] of Object.entries(ourHooks)) {
  const kept = (settings.hooks[event] || []).map(g => ({ ...g, hooks: (g.hooks || []).filter(h => !String(h.command || "").includes(H)) })).filter(g => g.hooks.length);
  settings.hooks[event] = [...kept, ...groups];
}
// Saving notes must not stop for an "Allow?" click: edits are accepted, and the vault counts as
// a working folder wherever Claude starts. Sending, buying and deleting still ask (source-check guards them).
// Claude Code's built-in memory folder would compete with the vault; the vault is the only memory.
settings.autoMemoryEnabled = false;
settings.permissions ||= {};
settings.permissions.defaultMode ||= "acceptEdits";
const dirs = new Set(settings.permissions.additionalDirectories || []); dirs.add(VAULT);
settings.permissions.additionalDirectories = [...dirs];
const allow = new Set(settings.permissions.allow || []);
for (const r of [`Bash(git -C ${VAULT}:*)`, "Bash(git status:*)", "Bash(git log:*)", "Bash(git diff:*)",
  `Bash(bash ${path.join(SKILL, "run-tests.sh")})`, "Bash(bash ~/.claude/skills/system/run-tests.sh)",
  `Bash(node ${path.join(SKILL, "import-history.mjs")}:*)`, "Bash(gh auth status)", "Bash(ls:*)", "Bash(wc:*)"]) allow.add(r);
settings.permissions.allow = [...allow];
fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n");
done.push(settingsFile);

// 6. The vault becomes a git repository with a first restore point.
const git = (...a) => execFileSync("git", ["-C", VAULT, ...a], { stdio: ["ignore", "pipe", "pipe"] }).toString().trim();
if (!fs.existsSync(path.join(VAULT, ".git"))) {
  git("init", "-q", "-b", "main");
  git("config", "user.name", NAME);
  git("config", "user.email", `${NAME.toLowerCase().replace(/[^a-z0-9]+/g, ".")}@vault.local`);
}
git("add", "-A");
try { git("commit", "-q", "-m", `Vault kit installed ${DATE}`); } catch {}

console.log(`Installed for ${NAME}.\n  vault: ${VAULT}\n  files written: ${done.length}\n  hooks: ${settingsFile}\nNext: open Claude Code and follow SETUP.md.`);
