// RONIN Island: a Dynamic-Island style strip at the top of the screen.
// Collapsed = pill. Open = panel + bottom tab bar (Home, Claude, Music, Messages*, Focus, Today) + volume control.
// Data: Claude Code sessions (hook.mjs state files), media (Windows media session via media.ps1),
// system volume (vol.ps1), today's schedule (HUD sidecar, ronin-hud/hud_server.py),
// *optional local inbox endpoint (island.messages in config.json; off by default, tab hidden when off).
// Config: ../config.json (written by install.ps1; see config.example.json). Everything is optional.
const { app, BrowserWindow, ipcMain, screen } = require("electron");
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");

const HERE = __dirname;
const SESS = path.join(HERE, "state", "sessions");
const LOG = path.join(HERE, "island.log");
const PILL = { w: 380, h: 30 };
const OPEN = { w: 760, h: 300 };

function loadConfig() {
  try { return JSON.parse(fs.readFileSync(path.join(HERE, "..", "config.json"), "utf8")); } catch { return {}; }
}
const CFG = loadConfig();
const HUD_PORT = Number((CFG.hud && CFG.hud.port) || 8797);

// Optional messages inbox: a LOCAL http endpoint (127.0.0.1 / localhost only) that answers
// POST {n} with [{from, text, ts}] (or {messages: [...]}). The secret is read here and never reaches the renderer.
const expandEnv = (s) => String(s || "").replace(/%([^%]+)%/g, (m, k) => process.env[k] ?? m);
const MSG = (() => {
  const m = (CFG.island && CFG.island.messages) || {};
  if (!m.enabled || !m.url) return null;
  try {
    const u = new URL(String(m.url));
    if (u.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(u.hostname)) return null;
    const sf = expandEnv(m.secret_file);
    return { url: u.toString(), secretFile: sf ? path.resolve(HERE, "..", sf) : "", header: String(m.secret_header || "x-island-secret") };
  } catch { return null; }
})();

let win, quitting = false;
let media = null, mediaState = { ok: false };
let vol = null, volState = { ok: false };

if (!app.requestSingleInstanceLock()) app.quit();

function place(size) {
  const d = screen.getPrimaryDisplay();
  const x = Math.round(d.workArea.x + (d.workArea.width - size.w) / 2);
  // Hang from the very top edge like a notch.
  win.setBounds({ x, y: d.bounds.y, width: size.w, height: size.h }, false);
}

// Long-running Windows PowerShell 5.1 helper: JSON lines on stdout, commands on stdin; restarts itself after 5 s.
function startHelper(file, onState, setProc) {
  const p = spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(HERE, file)], { windowsHide: true });
  setProc(p);
  let buf = "";
  p.stdout.on("data", (d) => {
    buf += d.toString("utf8");
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      try { onState(JSON.parse(line)); } catch {}
    }
  });
  p.stdin.on("error", () => {});
  p.on("exit", () => { setProc(null); if (!quitting) setTimeout(() => startHelper(file, onState, setProc), 5000); });
}

function readSessions() {
  try {
    return fs.readdirSync(SESS).filter((f) => f.endsWith(".json")).map((f) => {
      try { return JSON.parse(fs.readFileSync(path.join(SESS, f), "utf8")); } catch { return null; }
    }).filter(Boolean);
  } catch { return []; }
}

function getJSON(url, headers = {}, body = null) {
  return new Promise((resolve) => {
    const u = new URL(url);
    const req = http.request({ hostname: u.hostname, port: u.port, path: u.pathname + u.search, method: body ? "POST" : "GET", headers, timeout: 1500 }, (res) => {
      let d = ""; res.on("data", (c) => (d += c)); res.on("end", () => { try { resolve(JSON.parse(d)); } catch { resolve(null); } });
    });
    req.on("error", () => resolve(null)); req.on("timeout", () => { req.destroy(); resolve(null); });
    if (body) req.write(body);
    req.end();
  });
}

// messages: null = endpoint down, [] = none; only sender, first line (<=140 chars) and time reach the renderer.
let extras = { schedule: null, agent: CFG.agent_name || "RONIN", messagesEnabled: !!MSG, messages: null };
async function refreshExtras() {
  const hud = await getJSON(`http://127.0.0.1:${HUD_PORT}/hud`);
  extras.schedule = hud && hud.schedule ? hud.schedule.rows : null;
  if (!MSG) return;
  try {
    const headers = { "content-type": "application/json" };
    if (MSG.secretFile) headers[MSG.header] = fs.readFileSync(MSG.secretFile, "utf8").trim();
    const r = await getJSON(MSG.url, headers, JSON.stringify({ n: 50 }));
    const list = Array.isArray(r) ? r : r && Array.isArray(r.messages) ? r.messages : null;
    extras.messages = list
      ? list.map((m) => ({
          from: String((m && (m.from ?? m.name)) ?? "?").slice(0, 60),
          text: (String((m && m.text) ?? "").split(/\r?\n/).find((l) => l.trim()) ?? "").slice(0, 140),
          ts: m && m.ts,
        }))
      : null;
  } catch { extras.messages = null; }
}

app.whenReady().then(() => {
  win = new BrowserWindow({
    width: PILL.w, height: PILL.h, frame: false, transparent: true, resizable: true, movable: false, minimizable: false, maximizable: false, thickFrame: false,
    alwaysOnTop: true, skipTaskbar: true, hasShadow: false, focusable: true, show: false,
    webPreferences: { preload: path.join(HERE, "preload.cjs"), contextIsolation: true, nodeIntegration: false },
  });
  win.setAlwaysOnTop(true, "screen-saver");
  win.setVisibleOnAllWorkspaces(true);
  place(PILL);
  // Dev/test only: ISLAND_DEMO=1 pins it open, ISLAND_TAB=<id> picks the starting tab, ISLAND_POP=vol opens the volume popover.
  const q = {};
  if (process.env.ISLAND_DEMO) q.demo = "open";
  if (process.env.ISLAND_TAB) q.tab = process.env.ISLAND_TAB;
  if (process.env.ISLAND_POP) q.pop = process.env.ISLAND_POP;
  win.loadFile(path.join(HERE, "index.html"), Object.keys(q).length ? { search: new URLSearchParams(q).toString() } : {});
  win.once("ready-to-show", () => win.showInactive());
  win.webContents.on("console-message", (_e, level, msg, line) => { try { fs.appendFileSync(LOG, `[renderer ${level}] ${msg} (${line})\n`); } catch {} });
  win.webContents.on("preload-error", (_e, p, err) => { try { fs.appendFileSync(LOG, `[preload] ${err}\n`); } catch {} });
  screen.on("display-metrics-changed", () => place(win.getBounds().width > PILL.w ? OPEN : PILL));
  startHelper("media.ps1", (s) => (mediaState = s), (p) => (media = p));
  startHelper("vol.ps1", (s) => (volState = s), (p) => (vol = p));
  refreshExtras(); setInterval(refreshExtras, 15000);
  // Some third-party taskbars/top bars are also topmost; when one (re)starts after us it covers the notch, so re-assert every few seconds.
  setInterval(() => { if (!win.isDestroyed()) { win.setAlwaysOnTop(true, "screen-saver"); win.moveTop(); } }, 5000);
});

ipcMain.handle("state", () => ({ sessions: readSessions(), media: mediaState, vol: volState, extras, now: Date.now() }));
ipcMain.on("size", (_e, open) => place(open ? OPEN : PILL));
ipcMain.on("media", (_e, cmd) => { if (media && ["toggle", "next", "prev"].includes(cmd)) media.stdin.write(cmd + "\n"); });
ipcMain.on("vol", (_e, cmd, arg) => {
  if (!vol) return;
  const n = Math.round(Number(arg));
  if (cmd === "set" && Number.isFinite(n)) vol.stdin.write(`set ${Math.max(0, Math.min(100, n))}\n`);
  else if (cmd === "step" && Number.isFinite(n)) vol.stdin.write(`step ${Math.max(-20, Math.min(20, n))}\n`);
  else if (cmd === "togglemute") vol.stdin.write("togglemute\n");
});
ipcMain.on("seen", (_e, id) => {
  const f = path.join(SESS, String(id).replace(/[^a-zA-Z0-9_-]/g, "") + ".json");
  try { const s = JSON.parse(fs.readFileSync(f, "utf8")); if (s.state === "done" && !s.seen) { s.seen = true; s.seenAt = Date.now(); fs.writeFileSync(f, JSON.stringify(s)); } } catch {}
});
ipcMain.on("forget", (_e, id) => { try { fs.rmSync(path.join(SESS, String(id).replace(/[^a-zA-Z0-9_-]/g, "") + ".json")); } catch {} });
ipcMain.on("quit", () => app.quit());
app.on("before-quit", () => { quitting = true; try { media && media.kill(); } catch {} try { vol && vol.kill(); } catch {} });
