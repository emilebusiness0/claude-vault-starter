#!/usr/bin/env node
// PostToolUse hook (Bash and MCP tools): one line per thing a turn DID that
// changes the world outside a note: a deploy, a push, a merge, a service
// restart, a POST to a real host, a message sent, a page published.
//
// Why (2026-09-29): the Cloudflare move was something a session did, not
// something the person said, and the old stop check only ever asked about their words.
// save-check reads this file at the end of the turn and lists these actions in
// its question, and refuses a bare "nothing to save" once when any happened, so
// the session cannot skip past its own biggest change. Read-only work is never
// logged: reading a page, git status, a curl GET, a search.
//
// Never blocks and never fails the tool: any error exits 0 with nothing said.
// Tests: action-log.test.sh beside it.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as KIT from "./kit.mjs";

const STATE = process.env.ACTION_LOG_STATE || path.join(os.homedir(), ".claude", "state", "vault-check");
let data;
try { data = JSON.parse(fs.readFileSync(0, "utf8")); } catch { process.exit(0); }
const tool = String(data?.tool_name || "");
const input = data?.tool_input || {};
const sid = String(data?.session_id || "unknown").replace(/[^\w.-]/g, "_");

// The vault's own commits and pushes are the autocommit hook's job, not news.
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const VAULT_REL = path.relative(os.homedir(), KIT.VAULT);
const VAULT_CMD = new RegExp(`(?:${esc(KIT.VAULT)}|~/${esc(VAULT_REL)}|\\$HOME/${esc(VAULT_REL)})(?![\\w-])`);
// A command counts only where it is a command: the first word of a segment, after
// && || ; | or a newline, past any VAR=x, sudo, time or npx. A heredoc body, an echo,
// a grep and a commit message that merely say "npm run deploy" are not one.
// merge-base and merge-tree are read-only, so a name ends at a hyphen too.
const END = String.raw`(?![\w-])`;
const BASH = new RegExp("^(?:" + [
  String.raw`(?:npm|pnpm|yarn)\s+(?:run\s+)?(?:deploy|publish)`,
  String.raw`wrangler\s+(?:deploy|publish|secret|pages|d1|kv|r2|rollback|delete|triggers)`,
  String.raw`netlify\s+(?:deploy|env:|sites:|link|unlink|switch|api\s+\w*(?:create|update|delete))`,
  String.raw`vercel\b.*(?:--prod|\bdeploy|\benv\b)`,
  String.raw`git(?:\s+-C\s+\S+)?\s+(?:push|merge|rebase|tag|reset\s+--hard|branch\s+-[dD])`,
  String.raw`gh\s+(?:pr\s+(?:merge|create|close|edit)|repo\s+(?:create|delete|edit|rename|archive)|release\s+(?:create|delete|edit|upload)|secret\s+(?:set|remove|delete)|workflow\s+(?:run|enable|disable))`,
  String.raw`launchctl\s+(?:kickstart|bootstrap|bootout|load|unload|enable|disable|remove)`,
  String.raw`crontab\s+(?:-[a-km-z]\w*|[^-\s]\S*)`,
  String.raw`turso\s+(?:db|auth|group)`,
  String.raw`npm\s+(?:publish|uninstall|i(?:nstall)?\s+-g)`,
  String.raw`brew\s+(?:install|uninstall|upgrade|tap)`,
  String.raw`(?:apt|apt-get)\s+(?:install|remove|purge|upgrade)`,
  String.raw`systemctl\s+(?:enable|disable|start|stop|restart)`,
  String.raw`(?:defaults\s+write|pmset|networksetup|scutil)`,
].join("|") + ")" + END);
// The commands of a line of shell, without heredoc bodies or wrappers.
const segments = cmd => cmd.replace(/<<-?\s*(['"]?)(\w+)\1[^\n]*\n[\s\S]*?\n\s*\2[ \t]*(?=\n|$)/g, "")
  .split(/&&|\|\||;|\||\n|\$\(|\(/)
  .map(x => x.trim().replace(/^(?:[A-Za-z_]\w*=\S*\s+)+/, "").replace(/^(?:sudo|time|nohup|command|exec)\s+/, "").replace(/^(?:npx|bunx|pnpm\s+dlx|pnpm\s+exec)\s+(?:-y\s+)?/, ""))
  .filter(Boolean);
const POST = /\bcurl\b[^|;&]*\s-X\s*(?:POST|PUT|PATCH|DELETE)\b/i;
const LOCAL = /(?:localhost|127\.0\.0\.1|\[::1\])/;

const MCP_DOES = /(?:^|_)(?:send|reply|forward|publish|create|update|delete|trash|share|launch|post|set|apply|label|unlabel|move|upload|draft|schedule)(?:_|$)/;
const MCP_READS = /(?:^|_)(?:get|list|search|read|query|find|lookup|check|whoami|status|analytics)(?:_|$)/;

let what = "";
if (tool === "Bash") {
  const cmd = String(input.command || "");
  const segs = segments(cmd);
  if (!VAULT_CMD.test(cmd) && (segs.some(x => BASH.test(x)) || segs.some(x => /^curl\b/.test(x) && POST.test(x) && !LOCAL.test(x)))) what = cmd;
} else if (tool.startsWith("mcp__")) {
  const name = tool.split("__").pop() || "";
  if (MCP_DOES.test(name) && !MCP_READS.test(name)) what = tool;
} else if (tool === "Artifact") {
  const a = String(input.action || "publish");
  if (["publish", "delete", "pin"].includes(a)) what = `Artifact ${a} ${input.url || input.file_path || ""}`;
}
if (!what) process.exit(0);

try {
  fs.mkdirSync(STATE, { recursive: true });
  const line = [Math.floor(Date.now() / 1000), tool, what.replace(/\s+/g, " ").trim().slice(0, 220)].join("\t") + "\n";
  fs.appendFileSync(path.join(STATE, `${sid}.actions`), line);
} catch {}
process.exit(0);
