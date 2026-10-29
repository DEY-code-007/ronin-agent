#!/usr/bin/env python3
"""RONIN event reminder. Python standard library only. Windows.

Task Scheduler runs this every 15 minutes (install.ps1 -RegisterTasks sets
that up). For every event in config.json -> reminders.events that starts
today, it fires once when the event is `lead_minutes` (default 120) away:
a Windows notification, then (optional) the line spoken out loud through
ElevenLabs. No key, no quota or no network -> the notification alone.

The time left is computed, not assumed: a run that fires late (the laptop
was asleep) says the real time left, and with less than `min_left_minutes`
(default 15) to go it stays silent. Each event fires at most once a day
(state in data/fired.json).

Config (../config.json):
  "reminders": {
    "lead_minutes": 120, "min_left_minutes": 15,
    "speak": false, "voice_id": "YOUR_ELEVENLABS_VOICE_ID",
    "model": "eleven_turbo_v2_5", "language_code": "en",
    "events": [{"name": "Gym", "days": ["Mon", "Wed"], "start": "19:00"}],
    "lines": ["{owner}, {event} starts in {left}. Wrap up and get ready."]
  }
The ElevenLabs key comes from the ELEVENLABS_API_KEY user environment
variable, never from a file. voice_id falls back to backtalk.json.

  pythonw remind.py          the scheduled run
  python remind.py --test    fire the first event now, as if it were lead_minutes away
"""
import ctypes
import json
import os
import random
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DATA = HERE / "data"
LOG = DATA / "remind.log"
FIRED = DATA / "fired.json"
BACKTALK_JSON = ROOT / "backtalk" / "backtalk.json"
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

DEFAULT_LINES = [
    "{owner}, {event} starts in {left}. Wrap up what you're doing and get ready.",
    "Heads up, {owner}: {event} in {left}. Eat something, pack your bag.",
]


def load_config():
    try:
        return json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def log(msg):
    DATA.mkdir(exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")


def say_left(minutes):
    """Minutes -> spoken English, rounded to the quarter hour."""
    q = max(15, round(minutes / 15) * 15)
    h, m = divmod(q, 60)
    parts = []
    if h:
        parts.append("1 hour" if h == 1 else f"{h} hours")
    if m:
        parts.append(f"{m} minutes")
    return " ".join(parts)


def event_days(ev):
    return {d.strip().lower()[:3] for d in ev.get("days", [])}


def minutes_to(ev, now):
    if DAYS[now.weekday()] not in event_days(ev):
        return None
    h, m = (int(x) for x in ev["start"].split(":"))
    start = now.replace(hour=h, minute=m, second=0, microsecond=0)
    return (start - now).total_seconds() / 60


def toast(title, body):
    # Windows' own notification API through PowerShell; no extra modules.
    esc = lambda s: s.replace("&", "&amp;").replace("<", "&lt;").replace("'", "''")
    ps = (
        "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > $null;"
        "[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] > $null;"
        "$x = New-Object Windows.Data.Xml.Dom.XmlDocument;"
        f"$x.LoadXml('<toast><visual><binding template=\"ToastGeneric\"><text>{esc(title)}</text><text>{esc(body)}</text></binding></visual></toast>');"
        "$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe';"
        "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))"
    )
    subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps],
                   creationflags=0x08000000, timeout=30)   # CREATE_NO_WINDOW


def speak(text, rc):
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        log("no ELEVENLABS_API_KEY, notification only")
        return
    voice = rc.get("voice_id")
    model = rc.get("model", "eleven_turbo_v2_5")
    if not voice or voice.startswith("YOUR_"):
        try:
            el = json.loads(BACKTALK_JSON.read_text(encoding="utf-8")).get("elevenlabs", {})
            voice, model = el.get("voice_id"), el.get("model", model)
        except (OSError, ValueError):
            voice = None
    if not voice:
        log("no ElevenLabs voice_id configured, notification only")
        return
    body = {"text": text, "model_id": model}
    if rc.get("language_code"):
        body["language_code"] = rc["language_code"]
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json",
                 "Accept": "audio/mpeg"})
    with urllib.request.urlopen(req, timeout=30) as r:
        audio = r.read()
    mp3 = Path(tempfile.gettempdir()) / "ronin_reminder.mp3"
    mp3.write_bytes(audio)
    # MCI plays mp3 natively on every Windows; "wait" blocks until done.
    mci = ctypes.windll.winmm.mciSendStringW
    mci("close ronin", None, 0, None)
    if mci(f'open "{mp3}" type mpegvideo alias ronin', None, 0, None):
        raise RuntimeError("MCI could not open the mp3")
    mci("play ronin wait", None, 0, None)
    mci("close ronin", None, 0, None)


def fired_today():
    try:
        data = json.loads(FIRED.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    today = datetime.now().date().isoformat()
    return data if data.get("date") == today else {"date": today, "events": []}


def main():
    cfg = load_config()
    rc = cfg.get("reminders", {})
    agent = cfg.get("agent_name", "RONIN")
    owner = cfg.get("owner_name", "boss")
    lead = float(rc.get("lead_minutes", 120))
    min_left = float(rc.get("min_left_minutes", 15))
    events = rc.get("events", [])
    lines = rc.get("lines") or DEFAULT_LINES
    test = "--test" in sys.argv
    state = fired_today()
    now = datetime.now()

    due = []
    if test and events:
        due = [(events[0], lead)]
    for ev in ([] if test else events):
        left = minutes_to(ev, now)
        key = f"{ev.get('name')}@{ev.get('start')}"
        if left is None or left > lead or key in state["events"]:
            continue
        if left < min_left:
            log(f"skip {key} (minutes left: {left:.0f})")
            state["events"].append(key)
            continue
        due.append((ev, left))
        state["events"].append(key)

    for ev, left in due:
        text = random.choice(lines).format(owner=owner, event=ev.get("name", "event"),
                                           left=say_left(left), agent=agent)
        try:
            toast(f"{agent} · {ev.get('name', 'Reminder')}", text)
        except Exception as e:
            log(f"toast failed: {e}")
        if rc.get("speak"):
            try:
                speak(text, rc)
                log(f"spoke: {text}")
            except Exception as e:
                log(f"voice failed ({e}), notification only: {text}")
        else:
            log(f"notified: {text}")

    if not test:
        DATA.mkdir(exist_ok=True)
        FIRED.write_text(json.dumps(state), encoding="utf-8")


if __name__ == "__main__":
    main()
