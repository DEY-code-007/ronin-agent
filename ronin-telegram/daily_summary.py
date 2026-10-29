#!/usr/bin/env python3
"""Daily Telegram summary from the laptop. Python standard library only.

Optional. Task Scheduler can run this every morning (install.ps1
-RegisterTasks adds it at 07:30, disabled until you enable it). It reads
today's blocks from the vault's schedule note, today's events from
config.json -> reminders.events, and the open tasks from Active
Priorities.md, then sends one message to your Telegram chat.

Secrets come from user environment variables, never from a file:
  TELEGRAM_BOT_TOKEN   your bot's token (@BotFather)
  TELEGRAM_CHAT_ID     your numeric chat id with the bot

Wording: config.json -> daily_summary.opener / .closer, with {owner},
{agent}, {weekday} and {date} placeholders.

  pythonw daily_summary.py          the scheduled run
  python daily_summary.py --test    send right now, marked as a test
  python daily_summary.py --print   print the message, send nothing
"""
import json
import os
import re
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LOG = HERE / "data" / "daily_summary.log"
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def load_config():
    try:
        return json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


CFG = load_config()
VAULT = Path(os.path.expandvars(CFG.get("vault_path", r"%USERPROFILE%\RONIN-memory")))
SCHEDULE_FILE = VAULT / CFG.get("hud", {}).get("schedule_note", "Weekly Schedule.md")
PRIORITIES_FILE = VAULT / "Active Priorities.md"


def log(msg):
    LOG.parent.mkdir(exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def today_blocks(now):
    text = read(SCHEDULE_FILE)
    parts = re.split(r"^## (.+)$", text, flags=re.MULTILINE)[1:]
    blocks = {k.strip(): v for k, v in zip(parts[0::2], parts[1::2])}
    block = blocks.get(WEEKDAYS[now.weekday()], "")
    return [line.strip()[2:].strip() for line in block.splitlines()
            if line.strip().startswith("- ") and line.strip()[2:].strip()]


def today_events(now):
    day = WEEKDAYS[now.weekday()][:3].lower()
    out = []
    for ev in CFG.get("reminders", {}).get("events", []):
        if day in {d.strip().lower()[:3] for d in ev.get("days", [])}:
            out.append(f"{ev.get('start', '?')} {ev.get('name', 'event')}")
    return sorted(out)


def open_tasks():
    text = read(PRIORITIES_FILE)
    m = re.search(r"### Open Tasks\n(.*?)(?:\n### |\Z)", text, re.DOTALL)
    lines = []
    for line in (m.group(1) if m else "").splitlines():
        line = line.strip()
        if line.startswith("- [ ]"):
            lines.append(re.sub(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]",
                                lambda x: x.group(2) or x.group(1), line[5:].strip()).replace("**", ""))
    return lines


def build_message(now, test=False):
    ds = CFG.get("daily_summary", {})
    fmt = dict(owner=CFG.get("owner_name", "boss"), agent=CFG.get("agent_name", "RONIN"),
               weekday=WEEKDAYS[now.weekday()], date=now.strftime("%Y-%m-%d"))
    lines = [ds.get("opener", "Good morning {owner}. Today is {weekday}, {date}.").format(**fmt)]
    blocks = today_blocks(now)
    lines.append("\nSchedule:" if blocks else "\nNothing on the schedule today.")
    lines += [f"- {b}" for b in blocks]
    events = today_events(now)
    if events:
        lines.append("\nEvents:")
        lines += [f"- {e}" for e in events]
    tasks = open_tasks()
    if tasks:
        lines.append("\nOpen tasks:")
        lines += [f"- {t}" for t in tasks[:15]]
    lines.append("\n" + ds.get("closer", "Let's get to work.").format(**fmt))
    if test:
        lines.append("\n[test message]")
    return "\n".join(lines)


def send(text):
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat = os.environ.get("TELEGRAM_CHAT_ID")
    if not token or not chat:
        raise RuntimeError("TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must both be set")
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=json.dumps({"chat_id": chat, "text": text[:4000]}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()


def main():
    now = datetime.now()
    text = build_message(now, test="--test" in sys.argv)
    if "--print" in sys.argv:
        sys.stdout.reconfigure(encoding="utf-8")
        print(text)
        return
    try:
        send(text)
        log("sent ok")
    except Exception as e:
        log(f"send failed: {e}")


if __name__ == "__main__":
    main()
