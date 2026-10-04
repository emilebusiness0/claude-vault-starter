// Shared settings and vault rules for every hook in this kit.
// Where the vault is and whose it is come from ~/.claude/vault-kit.json, written once by install.mjs,
// so no hook has a path or a name written into it.
// The note-kind rules below are the same ones the original system's morning audit uses, so a hook and
// a later audit can never disagree about what counts as a living note.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const HOME = os.homedir();
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(process.env.VAULT_KIT_CONFIG || path.join(HOME, ".claude", "vault-kit.json"), "utf8")); } catch {}
export const VAULT = process.env.VAULT_DIR || cfg.vault || path.join(HOME, "vault");
export const NAME = cfg.name || "the user";
export const MEMORY = cfg.memory || path.join(HOME, ".claude", "CLAUDE.md");

// Where knowledge lives, versus where machines write. Only knowledge is searched for stale facts.
export const KNOWLEDGE = ["feedback/", "personal/", "duo-vert/", "school/", "projects/", "research/topics/", "decisions/"];
export const MACHINE = ["queue/", "reports/", "research/20", ".smart-env/", ".git/", ".obsidian/"];
export const isKnowledge = p =>
  !MACHINE.some(m => p.startsWith(m)) &&
  (KNOWLEDGE.some(k => p.startsWith(k)) || ["README.md", "DECISIONS.md", "TODO.md"].includes(p));

// The files that tell Claude how to behave are knowledge too: a dead fact in one is acted on every session.
export const PROMPT_FILES = (vault = VAULT) => [
  path.join(vault, ".claude", "skills", "system", "SKILL.md"),
  path.join(HOME, ".claude", "CLAUDE.md"),
];

export const DEAD_MARKERS = /~~|retract|corrected|no longer|stopped being true|used to|moot|superseded|is not any more|was overruled|retired|historical|old rule/i;
export function deadPhrases(md = "") {
  const rows = [];
  for (const line of String(md).split("\n")) {
    const m = line.match(/^\|\s*`([^`]+)`\s*\|([^|]*)\|/);
    if (m) rows.push({ phrase: m[1].trim().toLowerCase(), now: m[2].trim() });
  }
  return rows;
}

export function splitProps(text = "") {
  const s = String(text);
  if (!s.startsWith("---\n")) return { props: [], body: s };
  const lines = s.split("\n");
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") return { props: lines.slice(1, i), body: "\n".repeat(i + 1) + lines.slice(i + 1).join("\n") };
  }
  return { props: [], body: s };
}

// current: what is true now, read whole. history: the dated story behind a current note.
// store: read by selection. index: a lookup table (DECISIONS.md and decisions/).
export const HISTORY_SUFFIX = "-history.md";
export const isRecord = f => /\d{4}-\d{2}-\d{2}/.test(path.basename(f)) || f.startsWith("reports/");
export function noteKind(file, text = "") {
  const declared = splitProps(text).props.join("\n").match(/^\s*kind:\s*["']?(history|store|current|index)\b/m)?.[1];
  if (declared) return declared;
  if (file.endsWith(HISTORY_SUFFIX) || isRecord(file)) return "history";
  return "current";
}

export const INDEX_ROW_WORDS = 80;
export const INDEX_CHARS = 60_000;
export const WORDS_RED = 3000;
export const wordCount = (text = "") => String(text).split(/\s+/).filter(Boolean).length;
