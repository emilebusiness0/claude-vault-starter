#!/usr/bin/env node
// Turns ChatGPT and Gemini exports into one plain-text digest per conversation, newest first, so a
// session can read old history in batches and save only the facts worth keeping into the vault.
// Usage: node import-history.mjs <folder with the unzipped exports> [out folder]
// Reads, never deletes. Formats change over time, so every parser is tolerant and reports what it skipped.
import fs from "node:fs";
import path from "node:path";

const root = process.argv[2];
if (!root) { console.error("usage: node import-history.mjs <folder> [out]"); process.exit(1); }
const out = process.argv[3] || path.join(root, "digests");
const MAX_MSG = 4000;           // a pasted document or a long code answer is cut, the gist survives
const convos = [];
const skipped = [];

const walk = (d, acc = []) => {
  let es = []; try { es = fs.readdirSync(d, { withFileTypes: true }); } catch { return acc; }
  for (const e of es) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (path.resolve(p) !== path.resolve(out)) walk(p, acc); }
    else acc.push(p);
  }
  return acc;
};
const clip = t => { t = String(t || "").replace(/\r/g, "").trim(); return t.length > MAX_MSG ? t.slice(0, MAX_MSG) + " [...cut]" : t; };
const stripHtml = h => String(h || "").replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n").replace(/<[^>]+>/g, "")
  .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim();
const day = t => { const d = new Date(t); return isNaN(d) ? "0000-00-00" : d.toISOString().slice(0, 10); };

// ChatGPT: conversations.json, an array of { title, create_time, mapping, current_node }.
function chatgpt(file, data) {
  for (const c of data) {
    if (!c || typeof c !== "object" || !c.mapping) continue;
    const msgs = [];
    let id = c.current_node;
    const seen = new Set();
    while (id && c.mapping[id] && !seen.has(id)) {          // follow the branch that was kept, back to the root
      seen.add(id);
      const m = c.mapping[id].message;
      if (m && m.content) {
        const role = m.author?.role;
        const parts = Array.isArray(m.content.parts) ? m.content.parts.filter(p => typeof p === "string") : (m.content.text ? [m.content.text] : []);
        const text = parts.join("\n").trim();
        if ((role === "user" || role === "assistant") && text) msgs.unshift({ role: role === "user" ? "ME" : "CHATGPT", text: clip(text) });
      }
      id = c.mapping[id].parent;
    }
    if (msgs.length) convos.push({ source: "ChatGPT", title: c.title || "(untitled)", date: day((c.create_time || 0) * 1000), msgs });
  }
}

// Gemini, conversation-shaped JSON: { title, create_time, entries: [{ role, text }] } (one file or an array).
function geminiConvos(file, data) {
  const list = Array.isArray(data) ? data : [data];
  for (const c of list) {
    const entries = c?.entries || c?.messages;
    if (!Array.isArray(entries)) continue;
    const msgs = entries.map(e => ({ role: /user/i.test(e.role || e.author || "") ? "ME" : "GEMINI", text: clip(e.text || e.content || "") })).filter(m => m.text);
    if (msgs.length) convos.push({ source: "Gemini", title: c.title || "(untitled)", date: day(c.create_time || c.created || 0), msgs });
  }
}

// Gemini through My Activity (MyActivity.json): one entry per prompt, the reply in safeHtmlItem. Grouped by day.
function geminiActivity(file, data) {
  const byDay = new Map();
  for (const a of data) {
    if (!a || !/gemini|bard/i.test(JSON.stringify(a.header || a.products || ""))) continue;
    const prompt = String(a.title || "").replace(/^(Prompted|Demandé|Asked)\s*/i, "").trim();
    const reply = stripHtml((a.safeHtmlItem || []).map(x => x.html).join("\n"));
    const d = day(a.time);
    if (!byDay.has(d)) byDay.set(d, []);
    if (prompt) byDay.get(d).push({ role: "ME", text: clip(prompt) });
    if (reply) byDay.get(d).push({ role: "GEMINI", text: clip(reply) });
  }
  for (const [d, msgs] of byDay) if (msgs.length) convos.push({ source: "Gemini", title: `Gemini, ${d}`, date: d, msgs: msgs.reverse() });
}

// Gemini through My Activity as HTML only: prompts and replies are in outer-cell blocks.
function geminiActivityHtml(file, html) {
  const blocks = html.split(/<div class="outer-cell/).slice(1);
  const byDay = new Map();
  for (const b of blocks) {
    if (!/gemini|bard/i.test(b.slice(0, 600))) continue;
    const text = stripHtml(b);
    const when = text.match(/([A-Z][a-z]{2,8} \d{1,2}, \d{4})/)?.[1];
    const d = day(when);
    if (!byDay.has(d)) byDay.set(d, []);
    byDay.get(d).push({ role: "ENTRY", text: clip(text) });
  }
  for (const [d, msgs] of byDay) convos.push({ source: "Gemini", title: `Gemini, ${d}`, date: d, msgs: msgs.reverse() });
}

for (const f of walk(root)) {
  const name = path.basename(f).toLowerCase();
  try {
    if (name.endsWith(".json")) {
      const data = JSON.parse(fs.readFileSync(f, "utf8"));
      if (Array.isArray(data) && data.some(c => c && c.mapping)) chatgpt(f, data);
      else if (Array.isArray(data) && data.some(a => a && (a.safeHtmlItem || a.header))) geminiActivity(f, data);
      else if ((Array.isArray(data) ? data : [data]).some(c => c && (c.entries || c.messages))) geminiConvos(f, data);
      else skipped.push(`${f} (json, not a chat format this knows)`);
    } else if (name.endsWith(".html") && /myactivity/i.test(name)) {
      geminiActivityHtml(f, fs.readFileSync(f, "utf8"));
    } else if (/\.(zip)$/.test(name)) {
      skipped.push(`${f} (still zipped: unzip it first)`);
    }
  } catch (e) { skipped.push(`${f} (${e.message.slice(0, 80)})`); }
}

convos.sort((a, b) => b.date.localeCompare(a.date));
fs.mkdirSync(out, { recursive: true });
const index = [];
convos.forEach((c, i) => {
  const slug = c.title.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "").slice(0, 50) || "untitled";
  const file = `${String(i + 1).padStart(4, "0")}-${c.date}-${c.source.toLowerCase()}-${slug}.txt`;
  const body = `${c.source}: ${c.title}\n${c.date}\n\n` + c.msgs.map(m => `${m.role}:\n${m.text}\n`).join("\n");
  fs.writeFileSync(path.join(out, file), body);
  index.push(`${file}\t${c.msgs.length} messages\t${body.length} chars`);
});
fs.writeFileSync(path.join(out, "INDEX.txt"), index.join("\n") + "\n");
console.log(`${convos.length} conversations written to ${out} (newest first; INDEX.txt lists them)`);
const by = s => convos.filter(c => c.source === s).length;
console.log(`ChatGPT: ${by("ChatGPT")}, Gemini: ${by("Gemini")}`);
if (skipped.length) console.log(`Skipped:\n  ${skipped.join("\n  ")}`);
if (!convos.length) process.exit(3);
