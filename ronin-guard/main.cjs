// RONIN Guard: laptop theft alarm for cafés and libraries (inspired by the Mac app "MacGuard").
// Arm it, walk away. Touching the keyboard/touchpad, closing the lid or pulling the charger starts a
// short countdown; without the PIN it becomes a full alarm: siren at 100 % volume, webcam photo, Telegram ping.
// Usage: electron.exe <this folder> [--arm | --disarm | --status]
// Env: TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID (user env vars; both needed for pings),
//      GUARD_QUIET=1 (test mode: no siren, no volume change, no Telegram).
const { app, BrowserWindow, ipcMain, powerMonitor, powerSaveBlocker, session } = require("electron");
const { spawn, execFileSync } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const HERE = __dirname;
const DATA = path.join(HERE, "data");
const SHOTS = path.join(DATA, "shots");
const PIN_FILE = path.join(DATA, "pin.json");
const LID_BACKUP = path.join(DATA, "lid-backup.json");
const LOG = path.join(DATA, "guard.log");
const CHAT_ID = process.env.TELEGRAM_CHAT_ID || "";
const QUIET = process.env.GUARD_QUIET === "1";
const GRACE_S = 10;      // after arming, time to walk away
const COUNTDOWN_S = 8;   // after a trigger, time to type the PIN before the siren
const MAX_WRONG = 3;

fs.mkdirSync(SHOTS, { recursive: true });
const log = (m) => { try { fs.appendFileSync(LOG, `${new Date().toISOString()} ${m}\n`); } catch {} };

if (!app.requestSingleInstanceLock()) app.quit();

let win, helper = null, blocker = null, poll = null, topTimer = null, countdown = null, volTimer = null;
let state = "idle";      // setup | grace | armed | countdown | alarm | done
let reason = "", wrong = 0, armedAt = 0, triggerShot = null;

// ---------- PIN ----------
const hasPin = () => fs.existsSync(PIN_FILE);
function setPin(pin) {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.scryptSync(pin, salt, 32).toString("hex");
  fs.writeFileSync(PIN_FILE, JSON.stringify({ salt, hash }));
}
function checkPin(pin) {
  try {
    const { salt, hash } = JSON.parse(fs.readFileSync(PIN_FILE, "utf8"));
    return crypto.timingSafeEqual(Buffer.from(hash, "hex"), crypto.scryptSync(String(pin), salt, 32));
  } catch { return false; }
}

// ---------- lid close action (so closing the lid doesn't put the laptop to sleep and kill the alarm) ----------
const PC = (args) => execFileSync("powercfg", args, { encoding: "utf8", windowsHide: true });
function readLid() {
  const out = PC(["/qh", "SCHEME_CURRENT", "SUB_BUTTONS", "LIDACTION"]);
  const ac = /Current AC Power Setting Index: 0x([0-9a-f]+)/i.exec(out), dc = /Current DC Power Setting Index: 0x([0-9a-f]+)/i.exec(out);
  return { ac: ac ? parseInt(ac[1], 16) : 1, dc: dc ? parseInt(dc[1], 16) : 1 };
}
function writeLid(ac, dc) {
  PC(["/setacvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "LIDACTION", String(ac)]);
  PC(["/setdcvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "LIDACTION", String(dc)]);
  PC(["/setactive", "SCHEME_CURRENT"]);
}
function lidOff() {
  try {
    if (!fs.existsSync(LID_BACKUP)) fs.writeFileSync(LID_BACKUP, JSON.stringify(readLid()));
    writeLid(0, 0); log("lid action -> do nothing");
  } catch (e) { log("lidOff failed " + e.message); }
}
function lidRestore() {
  try {
    if (!fs.existsSync(LID_BACKUP)) return;
    const b = JSON.parse(fs.readFileSync(LID_BACKUP, "utf8"));
    writeLid(b.ac, b.dc); fs.unlinkSync(LID_BACKUP); log(`lid action restored ac=${b.ac} dc=${b.dc}`);
  } catch (e) { log("lidRestore failed " + e.message); }
}

// ---------- Telegram ----------
async function tg(method, body) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (QUIET || !token || !CHAT_ID) { log(`tg skipped (${QUIET ? "quiet" : !token ? "no token" : "no chat id"}) ${method}`); return; }
  try {
    const r = await fetch(`https://api.telegram.org/bot${token}/${method}`, { method: "POST", body });
    if (!r.ok) log(`tg ${method} http ${r.status}`);
  } catch (e) { log(`tg ${method} failed ${e.message}`); }
}
function tgText(text) {
  const f = new FormData(); f.append("chat_id", CHAT_ID); f.append("text", text);
  return tg("sendMessage", f);
}
function tgPhoto(file, caption) {
  const f = new FormData(); f.append("chat_id", CHAT_ID); f.append("caption", caption);
  f.append("photo", new Blob([fs.readFileSync(file)], { type: "image/jpeg" }), path.basename(file));
  return tg("sendPhoto", f);
}
const stamp = () => new Date().toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" });

// ---------- helper (lid events + volume) ----------
function startHelper() {
  helper = spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(HERE, "helper.ps1")], { windowsHide: true });
  let buf = "";
  helper.stdout.on("data", (d) => {
    buf += d; let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (line === "lid 0") trigger("Lid closed");
      else if (line.startsWith("err")) log("helper " + line);
    }
  });
  helper.on("exit", (c) => log("helper exit " + c));
}
const volumeMax = () => { if (!QUIET && helper && helper.stdin.writable) helper.stdin.write("max\n"); };

// ---------- state machine ----------
function send(extra = {}) { if (win && !win.isDestroyed()) win.webContents.send("state", { state, reason, wrong, quiet: QUIET, grace: GRACE_S, countdown: COUNTDOWN_S, ...extra }); }

function arm() {
  if (!hasPin()) { state = "setup"; send(); return; }
  if (["grace", "armed", "countdown", "alarm"].includes(state)) return;
  state = "grace"; reason = ""; wrong = 0; armedAt = Date.now(); triggerShot = null;
  lidOff();
  blocker = powerSaveBlocker.start("prevent-display-sleep");
  send();
  setTimeout(() => {
    if (state !== "grace") return;
    state = "armed"; send(); log("armed");
    tgText(`🛡️ RONIN Guard armed (${stamp()}). The laptop is locked down.`);
  }, GRACE_S * 1000);
}

function trigger(why) {
  if (state !== "armed") return;
  state = "countdown"; reason = why; log("trigger: " + why);
  send({ snap: true });
  countdown = setTimeout(() => alarm(), COUNTDOWN_S * 1000);
}

function alarm() {
  if (state === "alarm" || state === "done") return;
  clearTimeout(countdown);
  state = "alarm"; log("ALARM: " + reason);
  send({ snap: true });
  volumeMax(); volTimer = setInterval(volumeMax, 1000);
  tgText(`🚨 ALARM! Someone touched your laptop: ${reason} (${stamp()}).\nThe siren is on and will not stop until the PIN is entered.`);
  if (triggerShot) tgPhoto(triggerShot, "📸 First touch");
}

function disarm(via) {
  const was = state;
  state = "done"; clearTimeout(countdown); clearInterval(volTimer);
  if (blocker !== null && powerSaveBlocker.isStarted(blocker)) powerSaveBlocker.stop(blocker);
  lidRestore(); log(`disarmed via ${via} (was ${was})`);
  send();
  const msg = was === "alarm" ? `✅ Alarm silenced (${via}, ${stamp()}). Guard is off.` : `🔓 RONIN Guard disarmed (${via}, ${stamp()}).`;
  Promise.resolve(was === "setup" ? null : tgText(msg)).finally(() => setTimeout(() => app.exit(0), 1500));
}

// ---------- IPC ----------
ipcMain.handle("set-pin", (_e, pin) => {
  if (!/^\d{4,8}$/.test(String(pin))) return false;
  setPin(String(pin)); state = "idle"; arm(); return true;
});
ipcMain.handle("pin", (_e, pin) => {
  if (state === "setup" || state === "done") return false;
  if (checkPin(pin)) { disarm("PIN"); return true; }
  wrong++; log("wrong pin " + wrong);
  if (state === "armed") trigger("Wrong PIN entered");
  else if (wrong >= MAX_WRONG) alarm();
  send(); return false;
});
ipcMain.on("input", (_e, what) => { if (state === "armed") trigger(what); });
ipcMain.on("shot", (_e, dataUrl) => {
  try {
    const file = path.join(SHOTS, `${new Date().toISOString().replace(/[:.]/g, "-")}.jpg`);
    fs.writeFileSync(file, Buffer.from(String(dataUrl).split(",")[1], "base64"));
    log("shot " + path.basename(file));
    if (state === "countdown" && !triggerShot) triggerShot = file;
    else if (state === "alarm") tgPhoto(file, "📸 During the alarm");
  } catch (e) { log("shot failed " + e.message); }
});

// ---------- app ----------
function command(argv) {
  if (argv.includes("--disarm")) { if (state === "idle" || state === "setup") app.exit(0); else disarm("remote"); }
  else arm();
}
app.on("second-instance", (_e, argv) => command(argv));

app.whenReady().then(() => {
  if (process.argv.includes("--status")) { console.log(fs.existsSync(LID_BACKUP) ? "lid-backup present" : "clean"); app.exit(0); return; }
  if (process.argv.includes("--disarm")) { lidRestore(); app.exit(0); return; }  // nothing running: just make sure the lid setting is back
  lidRestore();   // recover from a crash that left the lid setting changed
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(perm === "media"));
  session.defaultSession.setPermissionCheckHandler((_wc, perm) => perm === "media");
  win = new BrowserWindow({
    fullscreen: true, kiosk: true, frame: false, alwaysOnTop: true, skipTaskbar: false, backgroundColor: "#07080b", show: false,
    title: "RONIN Guard", icon: path.join(HERE, "assets", "ronin-guard.ico"), webPreferences: { preload: path.join(HERE, "preload.cjs"), contextIsolation: true, nodeIntegration: false, backgroundThrottling: false, autoplayPolicy: "no-user-gesture-required" },
  });
  win.setAlwaysOnTop(true, "screen-saver");
  win.on("close", (e) => { if (state !== "done" && state !== "setup") { e.preventDefault(); if (state === "armed") trigger("Tried to close the window"); } });
  win.on("blur", () => { if (state === "armed") trigger("Switched to another window"); setTimeout(() => { if (win && !win.isDestroyed() && state !== "done") { win.focus(); win.moveTop(); } }, 100); });
  win.loadFile(path.join(HERE, "index.html"));
  win.once("ready-to-show", () => { win.show(); win.focus(); command(process.argv); });
  topTimer = setInterval(() => { if (state !== "done" && !win.isDestroyed()) { win.setAlwaysOnTop(true, "screen-saver"); win.moveTop(); } }, 1000);
  startHelper();
  // System-wide input: idle time drops to 0 whenever anyone touches keyboard/touchpad/mouse.
  poll = setInterval(() => { if (state === "armed" && powerMonitor.getSystemIdleTime() === 0 && Date.now() - armedAt > (GRACE_S + 1) * 1000) trigger("Keyboard or touchpad touched"); }, 250);
  powerMonitor.on("on-battery", () => trigger("Charger unplugged"));
  powerMonitor.on("suspend", () => log("suspend while " + state));
  powerMonitor.on("lock-screen", () => trigger("Tried to lock the screen"));
});

app.on("before-quit", () => { lidRestore(); try { helper && helper.kill(); } catch {} });
process.on("uncaughtException", (e) => { log("uncaught " + (e && e.stack)); });
