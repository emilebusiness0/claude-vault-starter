#!/usr/bin/env node
// PreToolUse hook: before a send, a publish or a price/legal edit, the session must have OPENED the
// note behind the two hard rules that bear most on that action.
//
// Why (2026-09-30): hard-rules.md puts 37 of his rules word for word in every session, and says "open
// its note before acting". Nothing checked that it did. A quote without its story is how a rule gets
// obeyed to the letter and broken in spirit (the "vous lire" closing, the Lumen name, an unapproved
// legal edit). The research of 2026-09-29 (research/2026-09-29-how-others-build-a-vault-that-compounds,
// Part 5) names the same gap: the constraint block must be read, and reading must be checkable. This
// hook is the check, made from the session's own transcript, with no model call.
//
// What it does: classifies the tool call (send / publish / price / legal), picks the two rules from
// hard-rules.md that fit it best, looks in the session transcript for a tool call that opened each
// note, and denies the call once with the two quotes and their note paths when one was not opened.
// The session opens them and retries; a retry passes. At most 2 denials per rule per session, then it
// lets the call through and logs the skip, so a session that cannot open a note is never stuck.
//
// Fails open: any error, a missing transcript or a missing rules file lets the call through, silently.
// Every decision is a line in state/source-check/log.jsonl, so whether it fires, and on what, is measured.
// Tests: source-check.test.sh beside it.   `source-check --scan '<json tool call>'` prints the decision.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as KIT from "./kit.mjs";

const HOME = os.homedir();
const ROOT = path.join(import.meta.dirname, "..");
const VAULT = process.env.SOURCE_CHECK_VAULT || KIT.VAULT;
const RULES = process.env.SOURCE_CHECK_RULES || path.join(ROOT, "hard-rules.md");
const STATE = process.env.SOURCE_CHECK_STATE || path.join(HOME, ".claude", "state", "source-check");
const MAX_DENIALS = 2;
const PICK = 2;

// Which rules matter for which kind of action, most relevant first (labels as they appear in hard-rules.md).
const CLASS_RULES = {
  send: ["Sending", "Accounts", "Email drafts", "Passwords", "Dashes", "Human writing", "Sources"],
  publish: ["Sending", "Legal", "Money", "Dashes", "Good work"],
  price: ["Money", "Decisions", "Sources"],
  legal: ["Legal", "Decisions"],
};
// Words in the call that make one rule more relevant than its class position says.
const BOOSTS = [
  [/gmail|\bemail\b|subject|\bmail\b|@\w+\.\w+/i, "Email drafts", 5],
  [/\u2014/, "Dashes", 8],
  [/password|passwd|token|api[_-]?key|card number/i, "Passwords", 8],
  [/\b(buy|order|checkout|subscribe|billing|plan)\b/i, "Money", 4],
];

const allow = () => process.exit(0);

/** The hard rules: { label, quote, note } from `- Label: "quote" [[folder/note]]` lines. */
export function parseRules(text) {
  const out = [];
  for (const l of String(text).split("\n")) {
    const m = l.match(/^- ([^:]+): "(.*)" \[\[([^\]]+)\]\]\s*$/);
    if (m) out.push({ label: m[1].trim(), quote: m[2].replace(/\\"/g, '"'), note: m[3].trim() });
  }
  return out;
}

const MESSAGE_TOOL = /^(send_message|send_email|send_email_to|send_agent_email|send_dm|messages_send|social_publish|reply_comment|reply_comments_bulk|reply_private|inbox_reply|reply|forward|create_draft|update_draft)$/;
const PRICE_PATH = /(soumission|tarif|pricing|prix|proposal|proposition|quote|unit-sheet|service-list)/i;
const LEGAL_PATH = /(conditions|confidentialit|privacy|terms|politique|mentions-legales|contrat|contract)/i;
// A publish is a command the shell would run, at the start of a command. Words inside a heredoc or a quoted
// string are data: a test file or a note that mentions "npm run deploy" is not a deploy (it blocked its own tests).
const PUBLISH_CMD = /(?:^|[;&|(\n])\s*(?:\w+=\S+\s+)*(?:npx\s+)?(?:npm run deploy\b|wrangler (?:pages )?(?:deploy|publish)\b|netlify deploy\b|vercel (?:deploy|--prod)\b|git push\b|gh pr (?:create|merge)\b|gh release\b)/;
// The same without `git push`: what is left to gate once a push to the vault's own repo is set aside.
const PUBLISH_NOT_PUSH = /(?:^|[;&|(\n])\s*(?:\w+=\S+\s+)*(?:npx\s+)?(?:npm run deploy\b|wrangler (?:pages )?(?:deploy|publish)\b|netlify deploy\b|vercel (?:deploy|--prod)\b|gh pr (?:create|merge)\b|gh release\b)/;
// Pushing the vault (his memory, synced to his own private repo) is not publishing to the world (2026-09-30: it
// blocked the vault's own merge-and-push twice). It counts only when every directory the command names is the vault.
const escRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const VAULT_REL = path.relative(HOME, VAULT);
const VAULT_DIR = new RegExp(`(?:cd|-C)\\s+["']?((?:~|\\$HOME|${escRe(HOME)})\\/${escRe(VAULT_REL)})\\/?["']?(?=[\\s;&|)]|$)`, "g");
export function pushesOnlyTheVault(cmd, cwd = "") {
  const u = unquoted(cmd);
  if (PUBLISH_NOT_PUSH.test(u)) return false;
  const dirs = [...String(cmd).matchAll(/(?:\bcd|\s-C)\s+["']?([^\s"';&|)]+)/g)].map(m => m[1]);
  const named = [...String(cmd).matchAll(VAULT_DIR)].length;
  if (dirs.length) return named === dirs.length;                       // every cd / -C goes to the vault
  return !!cwd && (cwd === VAULT || cwd.startsWith(VAULT + "/"));    // no cd: the session is standing in it
}
const SEND_CMD = /(api\.telegram\.org\/bot[^ ]*\/send(Message|Photo|Document)|\bsendmail\b|osascript[^|]*Mail)/i;
const heredocs = c => c.replace(/<<-?\s*['"]?(\w+)['"]?[^\n]*\n[\s\S]*?\n\s*\1\b/g, "");
const unquoted = c => heredocs(c).replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, '""');

/** "send" | "publish" | "price" | "legal" | null. */
export function classify(tool, input = {}, cwd = "") {
  if (tool === "Bash") {
    const cmd = String(input.command || "");
    if (SEND_CMD.test(heredocs(cmd))) return "send";
    if (PUBLISH_CMD.test(unquoted(cmd))) return pushesOnlyTheVault(cmd, cwd) ? null : "publish";
    return null;
  }
  if (tool === "Artifact") {
    const a = input.action;
    return !a || a === "publish" ? "publish" : null;
  }
  if (/^(Write|Edit|MultiEdit)$/.test(tool)) {
    const p = String(input.file_path || "");
    if (p.startsWith(VAULT + "/") || p.includes("/.claude/")) return null; // vault and config edits are not the world
    if (LEGAL_PATH.test(path.basename(p))) return "legal";
    if (PRICE_PATH.test(path.basename(p))) return "price";
    return null;
  }
  if (tool.startsWith("mcp__") && !tool.startsWith("mcp__ccd_") && MESSAGE_TOOL.test(tool.split("__").pop())) return "send";
  return null;
}

/** The two rules that fit best: class order, plus a boost for words in the call itself. */
export function pickRules(rules, cls, callText, n = PICK) {
  const order = CLASS_RULES[cls] || [];
  const score = new Map();
  order.forEach((label, i) => score.set(label, 20 - i));
  for (const [re, label, w] of BOOSTS) if (re.test(callText)) score.set(label, (score.get(label) || 0) + w);
  return rules.filter(r => score.has(r.label)).sort((a, b) => score.get(b.label) - score.get(a.label)).slice(0, n);
}

/** Only a tool call that READS counts. A Write or a heredoc that merely contains the note's name (a test file, a hook) is not opening it. */
function isReading(b) {
  const name = String(b.name || "");
  if (name === "Read") return true;
  if (/vault_read|vault_get_document_map|read_file_content|download_file_content|open_file/.test(name)) return true;
  if (name === "Bash") {
    const cmd = String(b.input?.command || "");
    return /(^|[\s;&|(])(cat|head|tail|sed|less|more|bat|grep|rg|awk|wc|open)\s/.test(cmd) && !/<<|>>?\s*\S*\.(md|sh|js|json|txt)/.test(cmd);
  }
  return false;
}

/** Did a tool call in this session open the note? Looks only at tool_use inputs, never at chat text. */
export function noteOpened(transcriptFile, note) {
  let text;
  try { text = fs.readFileSync(transcriptFile, "utf8"); } catch { return null; }
  // the note by vault path, by bare file name, and by the memory folder's flat name (feedback_some_note.md)
  const needles = [`${note}.md`, note.replace(/^[^/]+\//, "") + ".md", note.replace(/\//g, "_").replace(/-/g, "_") + ".md"];
  for (const line of text.split("\n")) {
    if (!line.includes("tool_use") || !needles.some(n => line.includes(n))) continue;
    let d; try { d = JSON.parse(line); } catch { continue; }
    const blocks = Array.isArray(d?.message?.content) ? d.message.content : [];
    for (const b of blocks) {
      if (b?.type !== "tool_use" || !isReading(b)) continue;
      const s = JSON.stringify(b.input || {});
      if (needles.some(n => s.includes(n))) return true;
    }
  }
  return false;
}

export function denyText(cls, unread) {
  const what = { send: "sending or drafting a message", publish: "publishing or deploying", price: "a price or quote", legal: "legal wording" }[cls];
  const lines = unread.map(r => `- ${r.label}: "${r.quote}"  → open ${r.note}.md (in the vault) and read why`);
  return `Before ${what}: the two hard rules that bear on this are quoted word for word in your rules block, and the session has not opened the note behind ${unread.length === 1 ? "this one" : "them"} yet.\n${lines.join("\n")}\nOpen ${unread.length === 1 ? "it" : "each"} with Read, then retry the same call. It passes once the note has been opened.`;
}

const log = (entry) => {
  try { fs.mkdirSync(STATE, { recursive: true }); fs.appendFileSync(path.join(STATE, "log.jsonl"), JSON.stringify({ ts: new Date().toISOString(), ...entry }) + "\n"); } catch {}
};

export function decide(data) {
  const tool = String(data?.tool_name || "");
  const input = data?.tool_input || {};
  const cls = classify(tool, input, String(data?.cwd || ""));
  if (!cls) return { action: "allow" };
  let rules;
  try { rules = parseRules(fs.readFileSync(RULES, "utf8")); } catch { return { action: "allow", why: "no rules file" }; }
  const callText = JSON.stringify(input).slice(0, 20000);
  const picked = pickRules(rules, cls, callText);
  if (!picked.length) return { action: "allow", why: "no rule fits" };
  const transcript = data?.transcript_path;
  if (!transcript) return { action: "allow", why: "no transcript", cls };
  const opened = picked.map(r => noteOpened(transcript, r.note));
  if (opened.includes(null)) return { action: "allow", why: "transcript unreadable", cls };
  const unread = picked.filter((_, i) => !opened[i]);
  if (!unread.length) return { action: "allow", why: "notes already opened", cls, rules: picked.map(r => r.label) };

  // Denial budget per session and rule.
  const session = String(data?.session_id || "unknown").replace(/[^\w.-]/g, "_");
  const file = path.join(STATE, `${session}.json`);
  let counts = {}; try { counts = JSON.parse(fs.readFileSync(file, "utf8")); } catch {}
  const deniable = unread.filter(r => (counts[r.label] || 0) < MAX_DENIALS);
  if (!deniable.length) return { action: "allow", why: "denial budget spent", cls, rules: unread.map(r => r.label) };
  for (const r of deniable) counts[r.label] = (counts[r.label] || 0) + 1;
  try { fs.mkdirSync(STATE, { recursive: true }); fs.writeFileSync(file, JSON.stringify(counts)); } catch {}
  return { action: "deny", cls, rules: deniable.map(r => r.label), reason: denyText(cls, deniable) };
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("/source-check") || process.argv[1]?.endsWith("/source-check.mjs")) {
  let raw = "";
  try { raw = process.argv[2] === "--scan" ? process.argv[3] : fs.readFileSync(0, "utf8"); } catch { allow(); }
  let data; try { data = JSON.parse(raw); } catch { allow(); }
  let d;
  try { d = decide(data); } catch { allow(); }
  if (d.action === "deny") {
    log({ session: data.session_id, tool: data.tool_name, class: d.cls, rules: d.rules, decision: "deny" });
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: d.reason } }) + "\n");
  } else if (d.cls) {
    log({ session: data.session_id, tool: data.tool_name, class: d.cls, rules: d.rules, decision: "allow", why: d.why });
  }
  if (process.argv[2] === "--scan") console.log(d.action === "deny" ? d.reason : `(allow: ${d.why || "not an outgoing action"})`);
  process.exit(0);
}
