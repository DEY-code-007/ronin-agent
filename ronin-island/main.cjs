// RONIN Island: a Dynamic-Island style strip at the top of the screen.
// Tiles: Claude Code sessions (via hook.mjs state files), media (Windows media session via media.ps1),
// focus timer, and the next block of today's schedule (from the HUD sidecar, ronin-hud/hud_server.py).
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
const OPEN = { w: 760, h: 236 };

function loadConfig() {
  try { return JSON.parse(fs.readFileSync(path.join(HERE, "..", "config.json"), "utf8")); } catch { return {}; }
}
const CFG = loadConfig();
const HUD_PORT = Number((CFG.hud && CFG.hud.port) || 8797);

let win, media = null, mediaState = { ok: false };

if (!app.requestSingleInstanceLock()) app.quit();

function place(size) {
  const d = screen.getPrimaryDisplay();
  const x = Math.round(d.workArea.x + (d.workArea.width - size.w) / 2);
  // Hang from the very top edge like a notch.
  win.setBounds({ x, y: d.bounds.y, width: size.w, height: size.h }, false);
}

function startMedia() {
  media = spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(HERE, "media.ps1")], { windowsHide: true });
  let buf = "";
  media.stdout.on("data", (d) => {
    buf += d.toString("utf8");
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      try { mediaState = JSON.parse(line); } catch {}
    }
  });
  media.on("exit", () => { media = null; setTimeout(startMedia, 5000); });
}

function readSessions() {
  try {
    return fs.readdirSync(SESS).filter((f) => f.endsWith(".json")).map((f) => {
      try { return JSON.parse(fs.readFileSync(path.join(SESS, f), "utf8")); } catch { return null; }
    }).filter(Boolean);
  } catch { return []; }
}

function getJSON(url) {
  return new Promise((resolve) => {
    const u = new URL(url);
    const req = http.request({ hostname: u.hostname, port: u.port, path: u.pathname, method: "GET", timeout: 1500 }, (res) => {
      let d = ""; res.on("data", (c) => (d += c)); res.on("end", () => { try { resolve(JSON.parse(d)); } catch { resolve(null); } });
    });
    req.on("error", () => resolve(null)); req.on("timeout", () => { req.destroy(); resolve(null); });
    req.end();
  });
}

let extras = { schedule: null, agent: CFG.agent_name || "RONIN" };
async function refreshExtras() {
  const hud = await getJSON(`http://127.0.0.1:${HUD_PORT}/hud`);
  extras.schedule = hud && hud.schedule ? hud.schedule.rows : null;
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
  win.loadFile(path.join(HERE, "index.html"), process.env.ISLAND_DEMO ? { search: "demo=open" } : {});
  win.once("ready-to-show", () => win.showInactive());
  win.webContents.on("console-message", (_e, level, msg, line) => { try { fs.appendFileSync(LOG, `[renderer ${level}] ${msg} (${line})\n`); } catch {} });
  win.webContents.on("preload-error", (_e, p, err) => { try { fs.appendFileSync(LOG, `[preload] ${err}\n`); } catch {} });
  screen.on("display-metrics-changed", () => place(win.getBounds().width > PILL.w ? OPEN : PILL));
  startMedia();
  refreshExtras(); setInterval(refreshExtras, 30000);
  // Some third-party taskbars/top bars are also topmost; when one (re)starts after us it covers the notch, so re-assert every few seconds.
  setInterval(() => { if (!win.isDestroyed()) { win.setAlwaysOnTop(true, "screen-saver"); win.moveTop(); } }, 5000);
});

ipcMain.handle("state", () => ({ sessions: readSessions(), media: mediaState, extras, now: Date.now() }));
ipcMain.on("size", (_e, open) => place(open ? OPEN : PILL));
ipcMain.on("media", (_e, cmd) => { if (media && ["toggle", "next", "prev"].includes(cmd)) media.stdin.write(cmd + "\n"); });
ipcMain.on("seen", (_e, id) => {
  const f = path.join(SESS, String(id).replace(/[^a-zA-Z0-9_-]/g, "") + ".json");
  try { const s = JSON.parse(fs.readFileSync(f, "utf8")); if (s.state === "done" && !s.seen) { s.seen = true; s.seenAt = Date.now(); fs.writeFileSync(f, JSON.stringify(s)); } } catch {}
});
ipcMain.on("forget", (_e, id) => { try { fs.rmSync(path.join(SESS, String(id).replace(/[^a-zA-Z0-9_-]/g, "") + ".json")); } catch {} });
ipcMain.on("quit", () => app.quit());
app.on("before-quit", () => { try { media && media.kill(); } catch {} });
