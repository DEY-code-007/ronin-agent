#!/usr/bin/env python3
"""RONIN HUD sidecar. Python standard library only. Windows.

Reads the vault (never writes it) and serves one JSON document at
http://127.0.0.1:<port>/hud (default port 8797):

  schedule    today's blocks from the vault's schedule note (config
              hud.schedule_note, default "Weekly Schedule.md"): bullets
              like "- 09:00-10:30 Deep work" under "## Monday" headings
  priorities  unchecked items under "### Open Tasks" in Active Priorities.md
  projects    bullets under "### Active Projects" in Active Priorities.md
  log         today's daily note: "What Got Done" (done) and
              "What's Still In Progress" (open), across every session.
              No note for today yet -> the most recent daily note.

A second document, /sys, carries machine telemetry (CPU, RAM, battery),
the agent's services (face, voice, HUD, Telegram, vault sync), internet,
optional watched websites and optional weather. A background thread
refreshes it; requests only read the last snapshot.

RONIN Island reads /hud for its "Today" tile. A custom ai-visualizer face
can read both documents for an on-screen HUD.

Config: ../config.json (see config.example.json at the repo root).

  python hud_server.py            serve
  python hud_server.py --dump     print /hud once and exit
  python hud_server.py --dump-sys print /sys once (after ~9 s) and exit
"""
import csv
import ctypes
import io
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from ctypes import wintypes
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load_config():
    try:
        return json.loads((HERE.parent / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


CFG = load_config()
HUD = CFG.get("hud", {})
AGENT = CFG.get("agent_name", "RONIN")
VAULT = Path(os.path.expandvars(CFG.get("vault_path", r"%USERPROFILE%\RONIN-memory")))
PORT = int(HUD.get("port", 8797))  # never 8791: that is backtalk's single-instance lock
DAY_ROLLOVER_H = int(HUD.get("day_rollover_hour", 4))
SCHEDULE_NOTE = HUD.get("schedule_note", "Weekly Schedule.md")
SYNC_TASK = HUD.get("sync_task", rf"\{AGENT}\Vault Sync")
WATCH = HUD.get("watch_urls", [])          # [{"name": "...", "url": "https://..."}]
WEATHER = HUD.get("weather", {})           # {"enabled": true, "latitude": .., "longitude": ..}

WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
            "Saturday", "Sunday"]
TIME_RE = re.compile(r"(\d{1,2}:\d{2})(?:\s*-\s*(\d{1,2}:\d{2}))?")


def clean(text):
    """Markdown to plain HUD text: [[Link|alias]] -> alias, drop ** and `."""
    text = re.sub(r"\[\[([^\]|]+)\|([^\]]+)\]\]", r"\2", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    return text.replace("**", "").replace("`", "").strip()


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def section(text, heading):
    """Lines under the first matching heading."""
    found = sections(text, heading)
    return found[0] if found else []


def sections(text, heading):
    """Lines under every heading that starts with `heading`, each block
    ending at the next heading of the same or a higher level."""
    level = len(heading) - len(heading.lstrip("#"))
    out, cur = [], None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"^(#+)\s", s)
        if m:
            if cur is not None and len(m.group(1)) <= level:
                out.append(cur)
                cur = None
            if s.lower().startswith(heading.lower()):
                cur = []
                continue
        if cur is not None:
            cur.append(line)
    if cur is not None:
        out.append(cur)
    return out


def bullets(lines):
    items = []
    for line in lines:
        s = line.strip()
        if s.startswith("<!--"):
            continue
        if s.startswith("- ") or s.startswith("* "):
            body = s[2:].strip()
            if body:
                items.append(body)
    return items


def to_min(hhmm):
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def schedule(today):
    day = WEEKDAYS[today.weekday()]
    note = VAULT / SCHEDULE_NOTE
    if not note.exists():
        found = next(VAULT.rglob(Path(SCHEDULE_NOTE).name), None) if VAULT.exists() else None
        note = found or note
    rows = []
    for item in bullets(section(read(note), f"## {day}")):
        m = TIME_RE.match(item)
        if not m:
            continue
        label = clean(item[m.end():].lstrip(" —-–:"))
        rows.append({"start": m.group(1).zfill(5), "end": m.group(2).zfill(5) if m.group(2) else None,
                     "text": label})
    rows.sort(key=lambda r: to_min(r["start"]))
    return {"day": day, "source": note.stem, "rows": rows}


def priorities():
    text = read(VAULT / "Active Priorities.md")
    tasks = []
    for item in bullets(section(text, "### Open Tasks")):
        if not item.startswith("[ ]"):
            continue
        body = item[3:].strip()
        tag = None
        m = re.match(r"^\*\*\(([^)]+)\)\*\*\s*", body)
        if m:
            tag, body = m.group(1), body[m.end():]
        tasks.append({"tag": tag, "text": clean(body)})
    projects = []
    for item in bullets(section(text, "### Active Projects")):
        name, _, status = clean(item).partition(" — ")
        projects.append({"name": name.strip(), "status": status.strip()})
    return tasks, projects


def daily_log(today):
    notes = VAULT / "01 - Daily Notes"
    if not notes.exists():
        return {"date": None, "done": [], "open": []}
    target = next(notes.rglob(f"{today.isoformat()}.md"), None)
    if target is None:
        dated = [p for p in notes.rglob("*.md")
                 if re.fullmatch(r"\d{4}-\d{2}-\d{2}", p.stem)]
        target = max(dated, key=lambda p: p.stem, default=None)
    if target is None:
        return {"date": None, "done": [], "open": []}
    text = read(target)
    done, open_ = [], []
    for lines in sections(text, "### What Got Done"):
        done += [clean(b) for b in bullets(lines)]
    for lines in sections(text, "### What's Still In Progress"):
        open_ += [clean(b) for b in bullets(lines)]
    return {"date": target.stem, "done": done, "open": open_}


def build():
    now = datetime.now()
    today = now.date()
    # Until day_rollover_hour (default 04:00) the plan on screen is still the
    # evening that is running, not the day that technically started.
    plan_day = (now - timedelta(hours=DAY_ROLLOVER_H)).date()
    tasks, projects = priorities()
    return {"generated": now.isoformat(timespec="seconds"), "agent": AGENT,
            "schedule": schedule(plan_day), "priorities": tasks,
            "projects": projects, "log": daily_log(today)}


# ---------------------------------------------------------------- /sys
NO_WINDOW = 0x08000000  # CREATE_NO_WINDOW: no console flash under pythonw
# WMO weather codes -> short English label
WMO = {0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
       45: "Fog", 48: "Rime fog", 51: "Drizzle", 53: "Drizzle",
       55: "Heavy drizzle", 61: "Light rain", 63: "Rain",
       65: "Heavy rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow",
       80: "Showers", 81: "Showers", 82: "Violent showers",
       95: "Thunderstorm", 96: "Hail", 99: "Hail"}


class _Mem(ctypes.Structure):
    _fields_ = [("dwLength", wintypes.DWORD), ("dwMemoryLoad", wintypes.DWORD),
                ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]


class _Power(ctypes.Structure):
    _fields_ = [("ACLineStatus", ctypes.c_ubyte), ("BatteryFlag", ctypes.c_ubyte),
                ("BatteryLifePercent", ctypes.c_ubyte),
                ("SystemStatusFlag", ctypes.c_ubyte),
                ("BatteryLifeTime", wintypes.DWORD),
                ("BatteryFullLifeTime", wintypes.DWORD)]


def _filetimes():
    idle, kern, user = (wintypes.FILETIME() for _ in range(3))
    ctypes.windll.kernel32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kern),
                                          ctypes.byref(user))
    v = lambda ft: (ft.dwHighDateTime << 32) | ft.dwLowDateTime
    return v(idle), v(kern) + v(user)   # kernel time includes idle


_cpu_prev = None


def cpu_pct():
    global _cpu_prev
    now = _filetimes()
    prev, _cpu_prev = _cpu_prev, now
    if prev is None or now[1] == prev[1]:
        return None
    busy = 1 - (now[0] - prev[0]) / (now[1] - prev[1])
    return round(max(0.0, min(1.0, busy)) * 100)


def ram():
    m = _Mem()
    m.dwLength = ctypes.sizeof(_Mem)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    gb = 1024 ** 3
    return {"pct": m.dwMemoryLoad, "used": round((m.ullTotalPhys - m.ullAvailPhys) / gb, 1),
            "total": round(m.ullTotalPhys / gb, 1)}


def battery():
    p = _Power()
    ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(p))
    if p.BatteryFlag == 128 or p.BatteryLifePercent == 255:
        return None  # no battery
    return {"pct": p.BatteryLifePercent, "plugged": p.ACLineStatus == 1}


def port_open(port):
    with socket.socket() as s:
        s.settimeout(0.4)
        return s.connect_ex(("127.0.0.1", port)) == 0


def port_listening(port):
    # backtalk's 8791 instance lock listen(1)s but never accept()s, so connect
    # probes fill its backlog and then time out. Read the LISTENING state
    # instead; never bind 8791 from here.
    return f"127.0.0.1:{port} " in "".join(
        l for l in run(["netstat", "-ano", "-p", "TCP"]).splitlines(True) if "LISTENING" in l)


def http_ok(url, timeout=5):
    try:
        req = urllib.request.Request(url, method="HEAD",
                                     headers={"User-Agent": f"{AGENT}-HUD"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status < 400
    except Exception:
        return False


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=8,
                              creationflags=NO_WINDOW).stdout
    except Exception:
        return ""


def telegram_up():
    # The Telegram channel plugin's MCP server runs on Bun inside the
    # dedicated Telegram session; no bun.exe means no bot.
    return "bun.exe" in run(["tasklist", "/FI", "IMAGENAME eq bun.exe", "/NH"])


def vault_sync():
    out = run(["schtasks", "/query", "/tn", SYNC_TASK, "/v", "/fo", "csv"])
    rows = list(csv.DictReader(io.StringIO(out)))
    if not rows:
        return {"ok": False, "last": None}
    r = rows[0]
    return {"ok": r.get("Last Result", "").strip() == "0",
            "last": r.get("Last Run Time", "").strip()}


def weather():
    q = urllib.parse.urlencode({
        "latitude": WEATHER.get("latitude", 0), "longitude": WEATHER.get("longitude", 0),
        "current": "temperature_2m,weather_code,wind_speed_10m",
        "timezone": WEATHER.get("timezone", "auto")})
    with urllib.request.urlopen(f"https://api.open-meteo.com/v1/forecast?{q}", timeout=6) as r:
        cur = json.load(r)["current"]
    code = int(cur.get("weather_code", -1))
    return {"temp": round(cur["temperature_2m"]), "code": code,
            "text": WMO.get(code, "-"), "wind": round(cur.get("wind_speed_10m", 0))}


SYS = {"generated": None}
_slow = {"t": 0}


def refresh_sys():
    """Fast parts every 3 s; network, processes and weather every 60 s."""
    while True:
        try:
            snap = dict(SYS)
            snap.update({"cpu": cpu_pct(), "ram": ram(), "battery": battery(),
                         "services": {**SYS.get("services", {}),
                                      "face": port_open(8790),
                                      "voice": port_listening(8791),
                                      "hud": True}})
            if time.time() - _slow["t"] > 60:
                _slow["t"] = time.time()
                net = http_ok("https://1.1.1.1", 4) or http_ok("https://www.google.com", 4)
                snap["net"] = net
                snap["sites"] = {w.get("name", w.get("url")): (http_ok(w["url"]) if net else False)
                                 for w in WATCH if w.get("url")}
                snap["services"]["telegram"] = telegram_up()
                snap["sync"] = vault_sync()
                if net and WEATHER.get("enabled"):
                    try:
                        snap["weather"] = weather()
                    except Exception:
                        pass
            snap["generated"] = datetime.now().isoformat(timespec="seconds")
            SYS.clear()
            SYS.update(snap)
        except Exception as e:
            SYS["error"] = str(e)
        time.sleep(3)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/sys":
            self._send(json.dumps(SYS, ensure_ascii=False).encode())
            return
        if route != "/hud":
            self._send(b'{"error":"not found"}', 404)
            return
        try:
            self._send(json.dumps(build(), ensure_ascii=False).encode())
        except ConnectionError:
            pass
        except Exception as e:
            try:
                self._send(json.dumps({"error": str(e)}).encode(), 500)
            except ConnectionError:
                pass

    def _send(self, body, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        # Local only (bound to 127.0.0.1); CORS open so a local face page can fetch it.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    if "--dump" in sys.argv:
        sys.stdout.reconfigure(encoding="utf-8")
        print(json.dumps(build(), ensure_ascii=False, indent=2))
        sys.exit(0)
    if "--dump-sys" in sys.argv:
        sys.stdout.reconfigure(encoding="utf-8")
        threading.Thread(target=refresh_sys, daemon=True).start()
        time.sleep(9)
        print(json.dumps(SYS, ensure_ascii=False, indent=2))
        sys.exit(0)
    try:
        # Windows SO_REUSEADDR lets a second copy bind the same port, so
        # turn it off: a duplicate launch must fail here and exit.
        ThreadingHTTPServer.allow_reuse_address = False
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        print(f"port {PORT} busy, HUD server already running", flush=True)
        sys.exit(0)
    threading.Thread(target=refresh_sys, daemon=True).start()
    print(f"{AGENT} HUD on http://127.0.0.1:{PORT}/hud  (vault: {VAULT})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
