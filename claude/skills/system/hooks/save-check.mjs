#!/usr/bin/env node
// Stop hook: a turn may end only with a vault decision that holds up.
//
// Replaces ~/.claude/hooks/vault-stop-check.sh (2026-08-15 to 2026-09-29), which
// asked one question, "did the user correct you, decide something or share a
// durable fact?", and accepted any file touched this turn as proof. Three holes,
// measured on 2026-09-29 over 3,227 turns since 09-01:
//   1. It never asked what the session itself changed. On 2026-09-28 a session
//      moved duovert.ca from Netlify to Cloudflare, wrote the news into a history
//      log every turn, passed every check, and left four living notes saying
//      Netlify, the duo-vert skill included ("netlify deploy"), plus lanes/site.md,
//      the night's charter for the site, found the next morning.
//   2. A fresh file was proof, whatever it was. A status line in a log counted.
//   3. After one block it let the next stop through unchecked (it trusted
//      stop_hook_active, which any Stop hook's block sets).
// Sessions had also learned to write the decision before the hook asked: 5 to
// 10% of turns until 09-20, 34% on Opus 5.5 and 73% on Fable from 09-21, so the
// question itself was no longer being read.
//
// What this does instead, after the Mem0 update step (each new fact is compared
// with what memory already holds: add, update, delete or leave it) and the
// vault's own RETRACTED.md:
//   - SAVED needs a REPLACED line: the old wording each new fact replaces, "=>"
//     what is true now. Every living note, skill, the memory index and Lucia's
//     prompts are searched for that wording, and the turn cannot end while one
//     still says it unmarked. When none does, the wording becomes a RETRACTED row,
//     so the morning audit keeps hunting it for good.
//   - REPLACED: nothing, or NO_SAVE_NEEDED, is questioned once when the reply
//     says something switched or the prompt says "from now on".
//   - Its own count of blocks per turn, three at most, then the turn ends and
//     Emile is told what was left.
// Which files count as living, history or machine output is imported from
// Lucia's vault-audit.js, so this cannot disagree with the morning audit.
// Tests: save-check.test.sh beside it. Every stop is one line in save-check.log.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as KIT from "./kit.mjs";

const HOME = os.homedir();
const STATE = process.env.SAVE_CHECK_STATE || path.join(HOME, ".claude", "state", "vault-check");
const VAULT = process.env.SAVE_CHECK_VAULT || KIT.VAULT;
const AUDIT = process.env.SAVE_CHECK_AUDIT || path.join(import.meta.dirname, "kit.mjs");
const SKILLS = process.env.SAVE_CHECK_SKILLS || path.join(HOME, ".claude", "skills");
const MEMORY = process.env.SAVE_CHECK_MEMORY || KIT.MEMORY;
const MAX_BLOCKS = 3;
const HARD = process.env.SAVE_CHECK_HARD_RULES || path.join(import.meta.dirname, "..", "hard-rules.md");
const CANARY_FIRST = 2, CANARY_EVERY = 6; // which asks of a session carry the canary: the 2nd, then every 6th

let input;
try { input = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }
const sid = String(input?.session_id || "unknown").replace(/[^\w.-]/g, "_");
const reply = String(input?.last_assistant_message || "");
const decisionFile = path.join(STATE, `${sid}.decision`);
const read = f => { try { return fs.readFileSync(f, "utf8"); } catch { return null; } };
const startTs = Number((read(path.join(STATE, `${sid}.start`)) || "0").trim()) || 0;
const prompt = read(path.join(STATE, `${sid}.prompt`)) || "";
// What the turn DID (deploys, pushes, sends), one line each, written by action-log.
const actionList = [...new Set((read(path.join(STATE, `${sid}.actions`)) || "").split("\n").filter(Boolean)
  .map(l => l.split("\t")).filter(([t]) => startTs && Number(t) >= startTs).map(([, tool, what]) => (what || tool).slice(0, 140)))];
const actionText = actionList.length ? `This turn you ran, and none of it is a vault note:\n${actionList.slice(0, 6).map(a => `  - ${a}`).join("\n")}${actionList.length > 6 ? `\n  ...and ${actionList.length - 6} more` : ""}\nAsk of each: where does the vault say how this is done or where it lives, and does that still say the old way?` : "";
try { fs.mkdirSync(STATE, { recursive: true }); } catch {}

// ---------- this turn's own state: blocks so far, whether the nudge was asked ----------
const turnFile = path.join(STATE, `${sid}.turn.json`);
let turn = {};
try { turn = JSON.parse(read(turnFile) || "{}"); } catch {}
if (turn.start !== startTs) turn = { start: startTs, blocks: 0, nudged: false, reread: false, last: "" };
const saveTurn = () => { try { fs.writeFileSync(turnFile, JSON.stringify(turn)); } catch {} };

// save-check.log is what Lucia's board line reads. A probe run in the real state
// folder against any other vault logs beside it instead: on 2026-09-29 four probe
// sessions on a throwaway vault turned that line amber for a week of noise.
const realPath = p => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
const LOG_NAME = !process.env.SAVE_CHECK_STATE && realPath(VAULT) !== realPath(KIT.VAULT)
  ? "save-check.other-vault.log" : "save-check.log";
const log = (outcome, kind, extra = "") => {
  const line = [new Date().toISOString(), sid, outcome, kind, extra.replace(/[\t\n]/g, " ").slice(0, 200)].join("\t");
  try { fs.appendFileSync(path.join(STATE, LOG_NAME), line + "\n"); } catch {}
};
const block = (kind, message, short) => {
  // The cap is checked here, after the decision was read, so a right answer on
  // the last stop passes normally; only a fourth wrong one gives up.
  if (turn.blocks >= MAX_BLOCKS) {
    log("gaveup", kind, short);
    process.stdout.write(JSON.stringify({ systemMessage: `Vault check gave up after ${MAX_BLOCKS} tries this turn; what was left: ${short}. Ask the session to finish it.` }) + "\n");
    process.exit(0);
  }
  turn.blocks += 1; turn.last = short; saveTurn();
  log("block", kind, short);
  process.stderr.write(`${message}\n(Vault check ${turn.blocks} of ${MAX_BLOCKS} this turn.)\n`);
  process.exit(2);
};
const pass = (kind, extra = "", tell = "") => {
  log("pass", kind, extra);
  if (tell) process.stdout.write(JSON.stringify({ systemMessage: tell }) + "\n");
  process.exit(0);
};

const QUESTIONS = `Vault check before this turn ends. Three questions, about this turn only:
1. What is true now that the vault does not say yet? Count what ${KIT.NAME} said or decided AND what you did: something published, moved, switched, bought, priced, renamed, turned on or off, sent.
2. What did the vault say before about each of those? A new fact usually replaces an old one somewhere: a decisions row, a lane brief, a skill, the to-do list, a project note, MEMORY.md. Name the old wording; this check searches every living note and skill for it and will not let the turn end while one still says it.
3. Which note owns the current truth? A log, a history note or queue/STATUS.md alone is not a save.

Reply with just these lines (no tool call, nothing else; writing them to ${decisionFile} also works), either:
  SAVED: auto   (every vault file you wrote this turn) or paths: decisions/night.md research/index.md
  REPLACED: <old wording> => <what is true now, 8 words at most>
  (Paths relative to the vault, or absolute. One REPLACED line per old fact. The old wording is the few words other notes would share, like "hosted on wix", not the sentence you just edited; join two words that must share a line with &&, like: duovert.ca && netlify. Write REPLACED: nothing if this turn replaced nothing)
or:
  NO_SAVE_NEEDED: <why, in a few words>
${KIT.NAME} reads this reply on screen: keep it to those lines, no recap of what you saved. He sees the count from the hook itself.${actionText ? `\n\n${actionText}` : ""}`;

// From the second ask in a session the format is already in the conversation, so the
// ask is a few lines: what a check adds is carried through every later call.
const QUESTIONS_SHORT = `Vault check. Same three questions (what is true now, counting what you did; what the vault said before; which note owns it). Reply with only:
  SAVED: auto   (or <vault-relative paths>)   then   REPLACED: <old wording> => <now, 8 words at most>   (or REPLACED: nothing)
or
  NO_SAVE_NEEDED: <why, in a few words>
No recap; ${KIT.NAME} sees the count from the hook.${actionText ? `\n\n${actionText}` : ""}`;
const askedFile = path.join(STATE, `${sid}.asked`);

// ---------- the canary (2026-09-30) ----------
// hard-rules.md rides in every session (hooks/session-start), and a long session can lose it without
// anyone seeing. Every few asks this question carries one more line: the last four words of one hard
// rule, picked by label. A session that still has the block copies them; one that lost it cannot. A
// miss never blocks. It is logged to canary.log, and vault-turn-start.sh re-sends the block at his next
// message (the flag file `<session>.rules-lost`), so the loss is repaired as well as seen.
const canaryFile = path.join(STATE, `${sid}.canary.json`);
const norm = t => String(t).toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, " ").split(/\s+/).filter(Boolean);
const canaryState = () => { try { return JSON.parse(read(canaryFile) || "{}"); } catch { return {}; } };
const saveCanary = c => { try { fs.writeFileSync(canaryFile, JSON.stringify(c)); } catch {} };
const hardRules = () => {
  const out = [];
  for (const l of (read(HARD) || "").split("\n")) {
    const m = l.match(/^- ([^:]+): "(.*)" \[\[[^\]]+\]\]\s*$/);
    if (m) { const w = norm(m[2].replace(/\\"/g, '"')); if (w.length >= 7) out.push({ label: m[1].trim(), words: w.slice(-4) }); }
  }
  return out;
};
/** Called when the ask is built. Returns the extra line for the question, or "". */
const issueCanary = () => {
  const c = canaryState();
  if (c.pending && c.pending.turnStart === startTs) return canaryLine(c.pending);   // the same turn asks again
  c.asks = (c.asks || 0) + 1;
  c.pending = null;
  if (c.asks === CANARY_FIRST || (c.asks > CANARY_FIRST && c.asks % CANARY_EVERY === 0)) {
    const rules = hardRules();
    if (rules.length) {
      const r = rules[(Array.from(sid).reduce((a, ch) => a + ch.charCodeAt(0), 0) + c.asks) % rules.length];
      c.pending = { turnStart: startTs, label: r.label, words: r.words };
    }
  }
  saveCanary(c);
  return c.pending ? canaryLine(c.pending) : "";
};
const canaryLine = p => `\n  RULES: <the last four words of the hard rule labelled "${p.label}" in your hard_rules block>   (a third line; this is how the check sees that your rules are still loaded)`;
const canaryLog = (...f) => { try { fs.appendFileSync(path.join(STATE, "canary.log"), [new Date().toISOString(), sid, ...f].join("\t") + "\n"); } catch {} };
/** Called once a decision exists. Scores the RULES line, flags a miss, drops the pending canary. */
const scoreCanary = rawText => {
  const c = canaryState();
  if (!c.pending || c.pending.turnStart !== startTs) return;
  const line = rawText.split("\n").map(l => l.trim().replace(/^[-*>`_\s]+/, "")).find(l => /^RULES[*`_]*:/i.test(l)) || "";
  const have = new Set(norm(line.replace(/^RULES[*`_]*:/i, "")));
  const hits = c.pending.words.filter(w => have.has(w)).length;
  const ok = hits >= 3;
  canaryLog(ok ? "ok" : (line ? "wrong" : "unanswered"), c.pending.label, `${hits}/4`);
  if (!ok) { try { fs.writeFileSync(path.join(STATE, `${sid}.rules-lost`), c.pending.label); } catch {} }
  c.pending = null; saveCanary(c);
};

// ---------- the decision ----------
// The answer comes in the reply to a block (one model call) or in the file. Never the
// reply to the first stop of a turn: that is just his answer, which may quote the format.
const KEYED = /^(?:SAVED:|REPLACED:|RULES:|NO_SAVE_NEEDED\b)/;
const keyword = l => l.trim().replace(/^[-*>`_\s]+/, "").replace(/^(SAVED|REPLACED|RULES|NO_SAVE_NEEDED)[*`_]*(:?)[*`_]*/, "$1$2").trim();
const fromReply = turn.blocks >= 1 ? reply.split("\n").map(keyword).filter(l => KEYED.test(l)) : [];
if (fromReply.length) { try { fs.writeFileSync(decisionFile, fromReply.join("\n") + "\n"); } catch {} }
const raw = read(decisionFile);
if (raw === null || !raw.trim()) {
  const again = fs.existsSync(askedFile);
  try { fs.writeFileSync(askedFile, "1"); } catch {}
  block("none", (again ? QUESTIONS_SHORT : QUESTIONS) + issueCanary(), "no decision written");
}
// Lines in any order, with any markdown a model puts around the keyword
// ("**SAVED:**", "- REPLACED:", "`NO_SAVE_NEEDED`: ...").
try { scoreCanary(raw); } catch {}
const lines = raw.split("\n")
  .map(l => l.trim().replace(/^[-*>`_\s]+/, "").replace(/^(SAVED|REPLACED|NO_SAVE_NEEDED)[*`_]*(:?)[*`_]*/, "$1$2").trim())
  .filter(l => l && !/^RULES[*`_]*:/i.test(l));
const savedLine = lines.find(l => /^SAVED:/.test(l));
const noLine = lines.find(l => /^NO_SAVE_NEEDED\b/.test(l));
const first = savedLine || noLine || lines[0];
// The vault notes written since the turn began, offered when the decision
// leaves them out, so a fix is one copy rather than a search.
const writtenThisTurn = (all = false) => {
  const out = [];
  const visit = dir => {
    let es = []; try { es = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of es) {
      if (e.name.startsWith(".") && e.name !== ".claude") continue;
      const f = path.join(dir, e.name);
      // Not the files jobs write all day, and not RETRACTED.md, which this hook writes.
      if (/^(queue|reports|research\/2026[^/]*|RETRACTED\.md)(\/|$)/.test(path.relative(VAULT, f))) continue;
      if (e.isDirectory()) visit(f);
      else if (all || e.name.endsWith(".md")) { try { if (Math.floor(fs.statSync(f).mtimeMs / 1000) >= startTs) out.push(f); } catch {} }
    }
  };
  if (startTs) visit(VAULT);
  return all ? out : out.slice(0, 6);
};
const suggestSaved = () => { const w = writtenThisTurn(); return w.length ? `  SAVED: ${w.join(" ")}` : "  SAVED: /absolute/path/of/the/note.md"; };
if (!savedLine && !noLine && lines.some(l => /^REPLACED:/.test(l)))
  block("bad", `Vault check: your REPLACED line is read, but add a SAVED line naming the notes you wrote this turn, as the first line of ${decisionFile}. Written in the vault since this turn began:\n${suggestSaved()}\n(keep only the ones that hold what you saved; keep your REPLACED lines under it).`, "REPLACED with no SAVED line");

// A sentence that says something changed, in the reply or in what he typed.
const W = s => new RegExp(`(?<![\\p{L}\\p{N}_])(${s})(?![\\p{L}\\p{N}_])`, "giu");
const CHANGE_REPLY = W("switched|migrated|went live|is (?:now )?live (?:on|at)|now (?:runs|lives|publishes|deploys|points|uses|goes)|no longer|instead of|renamed|retired|superseded|moved (?:it |them |the \\w+ )?(?:to|from|off)|turned (?:off|on)|cancell?ed|désormais|n'est plus|remplacé");
const CHANGE_PROMPT = W("from now on|going forward|no longer|not anymore|instead of|switch(?:ed)? (?:it |that |us )?to|change (?:it|that|this) to|that'?s (?:wrong|not right)|dorénavant|à partir de maintenant|n'est plus|plus maintenant");
const changeSigns = () => {
  const found = [];
  for (const [label, text, re] of [["your reply", reply, CHANGE_REPLY], ["his message", prompt, CHANGE_PROMPT]]) {
    const words = [...new Set([...text.matchAll(re)].map(m => m[1].toLowerCase()))];
    if (!words.length) continue;
    const i = text.search(re);
    const s = Math.max(text.lastIndexOf(".", i) + 1, i - 120);
    found.push(`${label} says "${text.slice(s, i + 120).replace(/\s+/g, " ").trim()}" (${words.map(w => `"${w}"`).join(", ")})`);
  }
  if (actionList.length) found.push(`this turn you ran ${actionList.slice(0, 4).map(a => `"${a.slice(0, 90)}"`).join(", ")}${actionList.length > 4 ? ` and ${actionList.length - 4} more` : ""}`);
  return found;
};
const nudge = (kind, what) => {
  if (turn.nudged) return;
  const signs = changeSigns();
  if (!signs.length) return;
  turn.nudged = true;
  block(kind, `Vault check: ${what}, but ${signs.join("; and ")}.
If that changed something the vault described another way, name the old wording in a REPLACED line (${decisionFile}, format: REPLACED: <old wording> => <what is true now>) and save the note that owns it. If it truly replaced nothing, keep your decision as it is and stop again; this is asked once per turn.`, `asked about a change (${kind})`);
};

if (!savedLine && noLine) {
  const reason = first.replace(/^NO_SAVE_NEEDED\s*:?\s*/, "");
  if (reason.split(/\s+/).filter(Boolean).length < 2)
    block("NO", `Vault check: NO_SAVE_NEEDED needs a reason, so the choice is made rather than typed. Rewrite ${decisionFile} as: NO_SAVE_NEEDED: <why, in a few words>`, "NO_SAVE_NEEDED with no reason");
  nudge("NO", "you wrote NO_SAVE_NEEDED");
  pass("NO", reason);
}

if (!savedLine)
  block("bad", `Vault check: ${decisionFile} is unrecognised: it has no line starting SAVED: or NO_SAVE_NEEDED: (read "${first.slice(0, 80)}"). Rewrite it as either
${suggestSaved()}
  REPLACED: <old wording> => <what is true now>   (or REPLACED: nothing)
or
  NO_SAVE_NEEDED: <why, in a few words>`, "unrecognised decision");

// SAVED paths: absolute, ~/ or relative to the vault (shorter on screen, 2026-09-29),
// and a folder name with a space ("Duo Vert") stays whole. A relative path starts a
// new entry once the one before it is complete (ends in .md).
const tokens = first.replace(/^SAVED:\s*/, "").split(/\s+/).map(t => t.replace(/[,;]+$/, "")).filter(Boolean);
const expand = p => p.startsWith("~/") ? path.join(HOME, p.slice(2)) : p.startsWith("/") ? p : path.join(VAULT, p);
const isFile = p => { try { return fs.statSync(expand(p)).isFile(); } catch { return false; } };
const saved = [];
// "SAVED: auto" (2026-09-29): every file written in the vault this turn, so the reply is one short line.
const auto = tokens.length === 1 && tokens[0].toLowerCase() === "auto";
if (auto) saved.push(...writtenThisTurn(true));
for (const t of auto ? [] : tokens) {
  if (t.startsWith("/") || t.startsWith("~") || !saved.length || isFile(saved[saved.length - 1])) saved.push(t);
  else saved[saved.length - 1] += " " + t;
}
const stale = saved.filter(p => {
  try { return Math.floor(fs.statSync(expand(p)).mtimeMs / 1000) < startTs; } catch { return true; }
});
if (!saved.length || stale.length)
  block("SAVED", `Vault check: ${decisionFile} names files that were not written this turn or do not exist: ${stale.join(" ") || (auto ? "(SAVED: auto found nothing written in the vault this turn; name the paths outside it)" : "(none named)")}. Write them, then stop again.`, "SAVED file not written this turn");

const replacedLines = lines.filter(l => /^REPLACED:/.test(l)).map(l => l.replace(/^REPLACED:\s*/, ""));
if (!replacedLines.length)
  block("SAVED", `Vault check: you saved ${saved.map(p => path.basename(p)).join(", ")}. Question 2 still needs an answer: what did the vault say before? Add one line per old fact to ${decisionFile}:
  REPLACED: <old wording, as notes would say it> => <what is true now>
or, if this turn only added something new:
  REPLACED: nothing
Every living note and skill will be searched for the old wording.`, "SAVED with no REPLACED line");

const replaced = [];
for (const r of replacedLines) {
  if (/^nothing\b/i.test(r)) continue;
  const arrow = r.indexOf("=>");
  if (arrow === -1)
    block("SAVED", `Vault check: "REPLACED: ${r}" needs what is true now after "=>": REPLACED: <old wording> => <what is true now>.`, "REPLACED without =>");
  const old = r.slice(0, arrow).trim().replace(/^["“]|["”]$/g, "");
  const now = r.slice(arrow + 2).trim();
  if (/[`|]/.test(old))
    block("SAVED", `Vault check: "${old}" has a backtick or a pipe; RETRACTED.md rows cannot hold either. Write the old wording as plain words.`, "phrase with backtick or pipe");
  const terms = old.split("&&").map(t => t.trim().toLowerCase()).filter(Boolean);
  if (!terms.length || terms.some(t => t.length < 3) || terms.join(" ").length < 6)
    block("SAVED", `Vault check: "${old}" is too short to search for without false hits. Use the words a note would actually say, or pair two with &&.`, "phrase too short");
  replaced.push({ old, terms, now: now || "see the saved note",
    matches: terms.length === 1 ? (low => low.includes(terms[0])) : (low => terms.every(t => wholeWord(t).test(low))) });
}
if (!replaced.length) {
  nudge("SAVED", "you wrote REPLACED: nothing");
  pass("SAVED", `nothing replaced; ${saved.length} file(s)`, `Vault: ${saved.length} saved, 0 replaced.`);
}

// ---------- re-read: is the new fact in a saved note? (2026-09-30) ----------
// SAVED is checked against the disk (the file exists and was written this turn). That cannot tell a
// write that landed from one that was overwritten, went to the wrong note or never said the fact. So
// the hook reads the saved notes back and looks for the words of "what is true now" in them. Lenient on
// purpose, since REPLACED's "now" is a paraphrase: a third of its words is enough, and it asks at most
// once per turn, so only a note that does not mention the new fact at all is sent back.
const REREAD_STOP = new Set(["the", "and", "that", "with", "from", "this", "now", "are", "was", "not", "for", "its", "has", "have", "but", "will", "into", "only", "per", "see", "saved", "note"]);
if (!turn.reread) {
  const have = new Set(norm(saved.map(p => read(expand(p)) || "").join("\n")));
  const gaps = [];
  for (const r of replaced) {
    const ws = [...new Set(norm(r.now))].filter(w => w.length >= 3 && !REREAD_STOP.has(w));
    if (!ws.length) continue;
    const hit = ws.filter(w => have.has(w)).length;
    if (hit < Math.ceil(ws.length / 3)) gaps.push({ now: r.now, missing: ws.filter(w => !have.has(w)) });
  }
  if (gaps.length) {
    turn.reread = true;
    block("REREAD", `Vault check: you saved ${saved.map(p => path.basename(p)).join(", ")} and wrote ${gaps.map(g => `"${g.now}"`).join(" and ")} as what is true now, but read back from disk those notes do not say ${gaps.map(g => g.missing.slice(0, 4).map(w => `"${w}"`).join(", ")).join(" or ")}. Open the note that owns the fact (Read it) and confirm the new wording is there; if it is, and only the wording differs from your REPLACED line, stop again and this passes.`, `saved note does not say "${gaps[0].now}"`);
  }
}

// ---------- the hunt ----------
let audit = {};
try { audit = await import(AUDIT); } catch {}
const FALLBACK_KNOWLEDGE = ["feedback/", "personal/", "duo-vert/", "research/topics/", "lanes/", "lumen/", "school/", "agents/", "decisions/"];
const FALLBACK_MACHINE = ["queue/", "reports/", "research/2026", ".smart-env/", ".git/"];
const isKnowledge = audit.isKnowledge || (p => !FALLBACK_MACHINE.some(m => p.startsWith(m)) &&
  (FALLBACK_KNOWLEDGE.some(k => p.startsWith(k)) || ["README.md", "DECISIONS.md", "project-current-todo-list.md"].includes(p)));
const noteKind = audit.noteKind || ((f, t) => f.endsWith("-history.md") || /^kind:\s*["']?history/m.test(String(t).split("\n---")[0]) ? "history" : "current");
const DEAD = audit.DEAD_MARKERS || /~~|retract|corrected|no longer|stopped being true|used to|moot|superseded|is not any more|was overruled|retired|historical|old rule/i;
// A single phrase is matched exactly as the audit matches a RETRACTED row (plain
// text, the audit's markers), because it becomes one: were this looser, the row
// it writes would turn the board red the next morning. A && pair never becomes a
// row, so its words match whole: "duovert.ca" is not "crm.duovert.ca".
const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const wholeWord = t => new RegExp(`(?<![\\p{L}\\p{N}_./-])${escape(t)}(?![\\p{L}\\p{N}_])`, "iu");

const walk = (dir, out = [], rel = "") => {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    if (e.name === ".git" || e.name === ".smart-env" || e.name === "node_modules") continue;
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) walk(path.join(dir, e.name), out, r);
    else if (e.name.endsWith(".md")) out.push(r);
  }
  return out;
};
// Hits are shown as full paths: a session in another folder, or a test vault,
// cannot mistake which file is meant (2026-09-29, a real session searched the
// wrong vault for "lanes/web.md").
const corpus = new Map(); // realpath -> the path as reached
const add = abs => { try { const real = fs.realpathSync(abs); if (!corpus.has(real)) corpus.set(real, abs); } catch {} };
for (const rel of walk(VAULT)) {
  if (rel === "RETRACTED.md") continue;
  const skillDoc = /^\.claude\/skills\/[^/]+\/[^/]+\.md$/.test(rel);
  if (!skillDoc && (!isKnowledge(rel) || /\d{4}-\d{2}-\d{2}/.test(path.basename(rel)))) continue;
  if (!skillDoc && noteKind(rel, read(path.join(VAULT, rel)) || "") === "history") continue;
  add(path.join(VAULT, rel));
}
for (const name of (() => { try { return fs.readdirSync(SKILLS); } catch { return []; } })()) {
  for (const f of (() => { try { return fs.readdirSync(path.join(SKILLS, name)); } catch { return []; } })())
    if (f.endsWith(".md")) add(path.join(SKILLS, name, f));
}
add(MEMORY);
for (const abs of (typeof audit.PROMPT_FILES === "function" ? audit.PROMPT_FILES(VAULT) : [])) add(abs);

const hits = [];
for (const [abs, shown] of corpus) {
  const text = read(abs);
  if (!text) continue;
  const ls = text.split("\n");
  for (let i = 0; i < ls.length; i++) {
    const low = ls[i].toLowerCase();
    for (const r of replaced) {
      if (!r.matches(low)) continue;
      // Prose is read with the five lines above it, as the audit does. A table row
      // stands alone (stricter than the audit, never looser): a "superseded" in the
      // row above says nothing about this one.
      const context = ls[i].trimStart().startsWith("|") ? ls[i] : ls.slice(Math.max(0, i - 5), i + 1).join("\n");
      if (DEAD.test(context)) continue;
      hits.push({ where: `${shown}:${i + 1}`, old: r.old, text: ls[i].trim().slice(0, 140) });
    }
  }
}
if (hits.length) {
  const shown = hits.slice(0, 15).map(h => `  ${h.where}\n      ${h.text}`).join("\n");
  block("SAVED", `Vault check: this turn replaced ${replaced.map(r => `"${r.old}"`).join(", ")}, but ${hits.length} line${hits.length === 1 ? "" : "s"} in living notes and skills still say it:
${shown}${hits.length > 15 ? `\n  ...and ${hits.length - 15} more` : ""}
Read each one. Change the lines about this to what is true now (${replaced.map(r => r.now).join("; ")}), or mark them as the past on the line itself (~~struck~~, "superseded", "no longer", "retired"). A hit about something else (another site, another product) is not wrong: make the REPLACED wording more specific instead, the words the stale notes use, or pair two words with &&. Then stop again; the search re-runs.`, `${hits.length} stale line(s): ${hits.slice(0, 3).map(h => h.where).join(", ")}`);
}

// ---------- nothing left: the morning audit hunts it from now on ----------
const retractedFile = path.join(VAULT, "RETRACTED.md");
const retracted = read(retractedFile);
let added = 0;
if (retracted !== null) {
  const have = new Set((audit.deadPhrases ? audit.deadPhrases(retracted) : []).map(r => r.phrase));
  for (const l of retracted.split("\n")) { const m = l.match(/^\|\s*`([^`]+)`\s*\|/); if (m) have.add(m[1].trim().toLowerCase()); }
  const owner = saved.map(expand).map(p => { try { return path.relative(fs.realpathSync(VAULT), fs.realpathSync(p)); } catch { return ""; } })
    .find(r => r && !r.startsWith("..") && r.endsWith(".md") && isKnowledge(r));
  const where = owner ? `[[${owner.replace(/\.md$/, "")}]]` : `session ${sid.slice(0, 8)}`;
  const d = new Date(); const today = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const rows = replaced.filter(r => r.terms.length === 1 && !have.has(r.terms[0]))
    .map(r => `| \`${r.old}\` | ${r.now.replace(/\|/g, "/").replace(/\n/g, " ")} | ${today} | ${where} |`);
  if (rows.length) {
    try { fs.appendFileSync(retractedFile, (retracted.endsWith("\n") ? "" : "\n") + rows.join("\n") + "\n"); added = rows.length; } catch {}
  }
}
pass("SAVED", `${replaced.length} replaced, 0 left, ${added} row(s) added`,
  `Vault: ${saved.length} saved, ${replaced.length} replaced (${corpus.size} notes searched, none stale)${added ? `, ${added} retired` : ""}.`);
