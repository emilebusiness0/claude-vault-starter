#!/usr/bin/env node
// PostToolUse hook (Edit|Write|MultiEdit): when an edit leaves a vault note over
// the size the morning audit allows for a note read whole, tell the session that
// made the edit, once per note per session.
//
// Why: on 2026-09-28 twenty notes were over 3,000 words. The audit had flagged
// them red on the board every morning, and nobody acted, because the board is
// read by the person, not by the session that made the note grow. Sessions append a
// dated section, the file crosses the line, and the one reader with the context
// to split it has moved on. This puts the message in front of that reader, at
// the moment it happens. The rule itself (which files, which kinds, which
// ceiling) is imported from Lucia's vault-audit.js, so this can never disagree
// with the audit. Tests: note-size.test.sh beside it.
//
// It sees the Edit and Write tools only, never a shell write; the morning audit
// is the backstop for those. Never blocks, never fails the edit: any error exits
// 0 with nothing said.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as KIT from "./kit.mjs";

const HOME = os.homedir();
const VAULT = process.env.NOTE_SIZE_VAULT || KIT.VAULT;
const AUDIT = process.env.NOTE_SIZE_AUDIT || path.join(import.meta.dirname, "kit.mjs");
const STATE = process.env.NOTE_SIZE_STATE || path.join(HOME, ".claude", "state", "note-size");

const quiet = () => process.exit(0);

let input = "";
try { input = fs.readFileSync(0, "utf8"); } catch { quiet(); }
let data;
try { data = JSON.parse(input); } catch { quiet(); }
const filePath = data?.tool_input?.file_path;
const session = String(data?.session_id || "unknown").replace(/[^\w.-]/g, "_");
if (typeof filePath !== "string" || !filePath.endsWith(".md")) quiet();

let real, vault;
try { real = fs.realpathSync(filePath); vault = fs.realpathSync(VAULT); } catch { quiet(); }
if (!real.startsWith(vault + path.sep)) quiet();
const rel = path.relative(vault, real).split(path.sep).join("/");

let audit;
try { audit = await import(AUDIT); } catch { quiet(); }
const { isKnowledge, noteKind, wordCount, WORDS_RED, INDEX_CHARS } = audit;
if (typeof isKnowledge !== "function" || typeof noteKind !== "function" || typeof wordCount !== "function") quiet();
if (!isKnowledge(rel)) quiet();

let text;
try { text = fs.readFileSync(real, "utf8"); } catch { quiet(); }
const kind = noteKind(rel, text);
const words = wordCount(text);
const over =
  (kind === "current" && words > WORDS_RED) ||
  (kind === "index" && Number.isFinite(INDEX_CHARS) && text.length > INDEX_CHARS);
if (!over) quiet();

// Once per note per session.
const seenFile = path.join(STATE, `${session}.json`);
let seen = [];
try { seen = JSON.parse(fs.readFileSync(seenFile, "utf8")); } catch {}
if (!Array.isArray(seen)) seen = [];
if (seen.includes(rel)) quiet();
try {
  fs.mkdirSync(STATE, { recursive: true });
  fs.writeFileSync(seenFile, JSON.stringify([...seen, rel]));
} catch {}

const base = rel.replace(/\.md$/, "");
const message = kind === "index"
  ? `vault: ${rel} is now ${text.length.toLocaleString("en-US")} characters, over the ${INDEX_CHARS.toLocaleString("en-US")} an index may hold and still be read in one go. Shorten its longest rows (the story behind a row belongs in the file the row links to), or tell ${KIT.NAME} in one line that it crossed.`
  : `vault: ${rel} is now ${words.toLocaleString("en-US")} words, over the ${WORDS_RED.toLocaleString("en-US")} a note read whole may have. Do not keep appending. If this session is working on that topic, split it before you finish, the way the vault does: move the dated story word for word into ${base}-history.md (properties \`kind: history\` and \`current: "[[${base}]]"\`, a banner at the top naming the current note), rewrite ${rel} as what is true now with a link to the history note, then check every original line is in one of the two and the links still resolve. If this session is not the place for it, tell ${KIT.NAME} in one line which note crossed.`;

process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: message },
}) + "\n");
process.exit(0);
