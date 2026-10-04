#!/usr/bin/env node
// PostToolUse hook (Read): when a session opens a dated research note or report, show it the
// newer retracted facts and decisions that are about the same thing, once per note per session.
//
// Why (2026-09-29): the vault exam (Lucia server/vault-exam.js) asked a fresh session 43 questions
// whose answers had changed. Two of the real failures came from a dated research note that was
// true when it was written and never marked old: the CRM backup "goes to iCloud" (09-24 note; it
// moved to Google Drive the same evening) and GA4 "working since 2026-08-13" (09-18 note; it was
// found broken that day and has collected only since 09-09). Searching the vault for the dead
// phrase cannot find these, because the old note and the retraction word it differently. So the
// match here is by topic: the words a newer RETRACTED.md or decisions/ row shares with the note,
// weighted by how rare each word is across the vault. It says which newer row to check; it never
// says the note is wrong. Tests: newer-facts.test.sh beside it.
//
// Never blocks, never fails the read: any error exits 0 with nothing said.
// `newer-facts --scan <vault-relative note>` prints what it would say, for tuning.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as KIT from "./kit.mjs";

const HOME = os.homedir();
const VAULT = process.env.NEWER_FACTS_VAULT || KIT.VAULT;
const STATE = process.env.NEWER_FACTS_STATE || path.join(HOME, ".claude", "state", "newer-facts");
const MIN_SHARED = 3;       // a row needs this many words, and this minus one of them rare and shared
const MIN_MASS = +(process.env.NEWER_FACTS_MASS || 8);   // the shared rare words together must weigh this much (each rare word weighs 3 to about 6)
const RARE = +(process.env.NEWER_FACTS_RARE || 3);   // idf a word needs to count: in about 20 of 414 notes or fewer
const MAX_HINTS = 3;
const DATED = /^(research|reports)\/(\d{4}-\d{2}-\d{2})-/;

const quiet = () => process.exit(0);

const walk = (dir, out = []) => {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith(".") || e.name === "node_modules") continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith(".md")) out.push(p);
  }
  return out;
};

const tokens = text => {
  const set = new Set();
  for (const m of String(text).toLowerCase().matchAll(/[\p{L}\p{N}][\p{L}\p{N}_.-]*[\p{L}\p{N}]/gu)) {
    const t = m[0];
    // words of 4+ letters, plus short names that mix letters and digits (ga4, g-5x..), never plain numbers or dates
    if ((t.length < 4 && !(/\d/.test(t) && /\p{L}/u.test(t))) || /^\d+$/.test(t) || /^\d{4}-\d{2}-\d{2}$/.test(t)) continue;
    set.add(t);
  }
  return set;
};

const cells = line => line.replace(/^\s*\|/, "").replace(/\|\s*$/, "").split("|").map(s => s.trim());
const dateIn = s => (String(s).match(/\d{4}-\d{2}-\d{2}/) || [])[0];

/** Newer facts: RETRACTED.md rows (dead phrase | true now | when | where) and decision rows (question | answer | date | note). */
function factRows(vault) {
  const rows = [];
  const add = (file, label, body, when, where = "") => {
    if (!when) return;
    const links = [...String(where).matchAll(/\[\[([^\]|#]+)/g)].map(m => m[1].trim());
    rows.push({ file, label, body, when, links });
  };
  try {
    for (const l of fs.readFileSync(path.join(vault, "RETRACTED.md"), "utf8").split("\n")) {
      if (!l.startsWith("|")) continue;
      const c = cells(l);
      if (c.length >= 4) add("RETRACTED.md", c[0].replace(/`/g, ""), c[1], dateIn(c[2]), c[3]);
    }
  } catch {}
  try {
    for (const f of fs.readdirSync(path.join(vault, "decisions")).filter(n => n.endsWith(".md"))) {
      for (const l of fs.readFileSync(path.join(vault, "decisions", f), "utf8").split("\n")) {
        if (!l.startsWith("|")) continue;
        const c = cells(l);
        if (c.length >= 3) add(`decisions/${f}`, c[0], c[1], dateIn(c[2]), c[3]);
      }
    }
  } catch {}
  return rows;
}

/** How rare each word is across the vault: a word in every note (crm, lucia, duovert) weighs nothing. */
function idf(vault) {
  const df = new Map(); let n = 0;
  for (const f of walk(vault)) {
    let text; try { text = fs.readFileSync(f, "utf8"); } catch { continue; }
    n++;
    for (const t of tokens(text)) df.set(t, (df.get(t) || 0) + 1);
  }
  return t => Math.log((n + 1) / ((df.get(t) || 0) + 1));
}

export function hints(vault, rel, text) {
  const m = rel.match(DATED);
  if (!m) return [];
  const noteDate = m[2];
  const weight = idf(vault);
  const note = tokens(text);
  const out = [];
  for (const r of factRows(vault)) {
    if (r.when < noteDate) continue;   // same day counts: the 09-24 backup note and the row that replaced it are one evening apart
    // A row that cites this very note as its source is about it, whatever the words say.
    if (r.links.includes(rel.replace(/\.md$/, ""))) { out.push({ ...r, score: Infinity }); continue; }
    // Long answers dilute the match, so only the question or dead phrase and the start of the answer count.
    const rowTokens = tokens(`${r.label} ${r.body.slice(0, 220)}`);
    if (rowTokens.size < MIN_SHARED) continue;
    // Only words rare across the vault count: two rows that share "still", "does" and "open" with a
    // note are not about it. A match needs at least two shared rare words and most of the row's rare words.
    let shared = 0, k = 0;
    for (const t of rowTokens) {
      const w = weight(t);
      if (w < RARE) continue;
      if (note.has(t)) { shared += w; k++; }
    }
    if (k >= MIN_SHARED - 1 && shared >= MIN_MASS) out.push({ ...r, score: shared });
  }
  return out.sort((a, b) => b.score - a.score).slice(0, MAX_HINTS);
}

const clip = (s, n) => { s = String(s).replace(/\*\*/g, "").replace(/\s+/g, " ").trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s; };

export function message(rel, list) {
  const lines = list.map(h => `- ${h.file} (${h.when}): "${clip(h.label, 90)}" now: ${clip(h.body, 170)}`);
  return `vault: ${rel} was written before newer rows about the same things. Check these before relying on it; the newer row wins:\n${lines.join("\n")}`;
}

const resolveVault = () => { try { return fs.realpathSync(VAULT); } catch { return null; } };

if (process.argv[2] === "--scan") {
  const vault = resolveVault(); const rel = process.argv[3];
  const list = hints(vault, rel, fs.readFileSync(path.join(vault, rel), "utf8"));
  console.log(list.length ? message(rel, list) : "(silent)");
  process.exit(0);
}

let input = "";
try { input = fs.readFileSync(0, "utf8"); } catch { quiet(); }
let data;
try { data = JSON.parse(input); } catch { quiet(); }
const filePath = data?.tool_input?.file_path;
const session = String(data?.session_id || "unknown").replace(/[^\w.-]/g, "_");
if (typeof filePath !== "string" || !filePath.endsWith(".md")) quiet();

let real, vault;
try { real = fs.realpathSync(filePath); vault = resolveVault(); } catch { quiet(); }
if (!vault || !real.startsWith(vault + path.sep)) quiet();
const rel = path.relative(vault, real).split(path.sep).join("/");
if (!DATED.test(rel)) quiet();

let text;
try { text = fs.readFileSync(real, "utf8"); } catch { quiet(); }
let list;
try { list = hints(vault, rel, text); } catch { quiet(); }
if (!list.length) quiet();

const seenFile = path.join(STATE, `${session}.json`);
let seen = [];
try { seen = JSON.parse(fs.readFileSync(seenFile, "utf8")); } catch {}
if (!Array.isArray(seen)) seen = [];
if (seen.includes(rel)) quiet();
try { fs.mkdirSync(STATE, { recursive: true }); fs.writeFileSync(seenFile, JSON.stringify([...seen, rel])); } catch {}

process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: message(rel, list) } }) + "\n");
process.exit(0);
