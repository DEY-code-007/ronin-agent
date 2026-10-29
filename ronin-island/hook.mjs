// Claude Code hook -> RONIN Island session state.
// Usage (from ~/.claude/settings.json hooks): node "<install dir>/ronin-island/hook.mjs" <working|needs|done|end>
// Reads the hook payload from stdin (session_id, cwd, message) and writes state/sessions/<id>.json.
// Only the session id, working-folder name, state and timestamps are stored; nothing leaves the machine.
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "state", "sessions");
const kind = process.argv[2] || "working";

const input = await new Promise((resolve) => {
  let d = "";
  const done = () => resolve(d);
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (c) => (d += c));
  process.stdin.on("end", done);
  process.stdin.on("error", done);
  setTimeout(done, 1500); // never hang Claude
});
let p = {};
try { p = JSON.parse(input || "{}"); } catch {}
const id = String(p.session_id || "unknown").replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 64) || "unknown";
const file = join(DIR, `${id}.json`);

try {
  mkdirSync(DIR, { recursive: true });
  if (kind === "end") { if (existsSync(file)) rmSync(file); process.exit(0); }
  let prev = {};
  try { prev = JSON.parse(readFileSync(file, "utf8")); } catch {}
  const now = Date.now();
  const state = { ...prev, id, cwd: p.cwd || prev.cwd || "", label: basename(p.cwd || prev.cwd || "Claude"), state: kind, at: now };
  if (kind === "working" && prev.state !== "working") state.since = now;
  if (kind === "done") { state.doneAt = now; state.seen = false; }
  if (kind === "needs") state.message = String(p.message || "Waiting for approval").slice(0, 120);
  writeFileSync(file, JSON.stringify(state));
} catch {}
// Never block Claude: always exit 0 with no output.
process.exit(0);
